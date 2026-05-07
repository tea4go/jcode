use super::{Tool, ToolContext, ToolOutput};
use anyhow::Result;
use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{Value, json};

/// Web search using Bing HTML (no API key required)
pub struct WebSearchTool {
    client: reqwest::Client,
}

impl WebSearchTool {
    pub fn new() -> Self {
        Self {
            client: crate::provider::shared_http_client(),
        }
    }
}

#[derive(Deserialize)]
struct WebSearchInput {
    query: String,
    #[serde(default)]
    num_results: Option<usize>,
}

#[derive(Debug)]
struct SearchResult {
    title: String,
    url: String,
    snippet: String,
}

#[async_trait]
impl Tool for WebSearchTool {
    fn name(&self) -> &str {
        "websearch"
    }

    fn description(&self) -> &str {
        "Search the web."
    }

    fn parameters_schema(&self) -> Value {
        json!({
            "type": "object",
            "required": ["query"],
            "properties": {
                "intent": super::intent_schema_property(),
                "query": {
                    "type": "string",
                    "description": "Search query."
                },
                "num_results": {
                    "type": "integer",
                    "description": "Max results."
                }
            }
        })
    }

    async fn execute(&self, input: Value, _ctx: ToolContext) -> Result<ToolOutput> {
        let params: WebSearchInput = serde_json::from_value(input)?;
        let num_results = params.num_results.unwrap_or(8).min(20);

        // Use Bing HTML search
        let url = format!(
            "https://www.bing.com/search?q={}",
            urlencoding::encode(&params.query)
        );

        let response = self
            .client
            .get(&url)
            .header(
                reqwest::header::USER_AGENT,
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
            )
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("Bing search request failed: {}", e))?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!(
                "Bing search returned status: {}",
                response.status()
            ));
        }

        let html = response.text().await?;
        let results = parse_bing_results(&html, num_results);

        if results.is_empty() {
            return Ok(ToolOutput::new(format!(
                "No results found for: {}",
                params.query
            )));
        }

        // Format results
        let mut output = format!("Search results for: {}\n\n", params.query);

        for (i, result) in results.iter().enumerate() {
            output.push_str(&format!(
                "{}. **{}**\n   {}\n   {}\n\n",
                i + 1,
                result.title,
                result.url,
                result.snippet
            ));
        }

        Ok(ToolOutput::new(output))
    }
}

mod search_regex {
    use regex::Regex;
    use std::sync::OnceLock;

    fn compile_regex(pattern: &str, label: &str) -> Option<Regex> {
        match Regex::new(pattern) {
            Ok(regex) => Some(regex),
            Err(err) => {
                crate::logging::warn(&format!(
                    "websearch: failed to compile static regex {label}: {}",
                    err
                ));
                None
            }
        }
    }

    macro_rules! static_regex {
        ($name:ident, $pat:expr_2021) => {
            pub fn $name() -> Option<&'static Regex> {
                static RE: OnceLock<Option<Regex>> = OnceLock::new();
                RE.get_or_init(|| compile_regex($pat, stringify!($name)))
                    .as_ref()
            }
        };
    }

    // Bing result blocks: <li class="b_algo"> ... </li>
    static_regex!(
        result_block,
        r#"<li[^>]*class="[^"]*b_algo[^"]*"[^>]*>(.*?)</li>"#
    );
    // Title link inside result block: <h2><a href="URL" ...>TITLE</a></h2>
    static_regex!(
        result_link,
        r#"<h2[^>]*><a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a></h2>"#
    );
    // Caption/snippet: <p class="b_lineclamp2">TEXT</p> or <div class="b_caption"><p>...</p>
    static_regex!(
        result_snippet,
        r#"(?:<p[^>]*class="b_lineclamp[^"]*"[^>]*>([\s\S]*?)</p>|<div[^>]*class="b_caption"[^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)</p>)"#
    );
    static_regex!(tag, r"<[^>]+>");
}

fn parse_bing_results(html: &str, max_results: usize) -> Vec<SearchResult> {
    let mut results = Vec::new();

    let (Some(result_block), Some(result_link), Some(result_snippet), Some(tag)) = (
        search_regex::result_block(),
        search_regex::result_link(),
        search_regex::result_snippet(),
        search_regex::tag(),
    ) else {
        return results;
    };

    // First extract result blocks, then parse each block
    for block_cap in result_block.captures_iter(html) {
        if results.len() >= max_results {
            break;
        }

        let block = &block_cap[1];

        // Extract link and title from block
        let (url, title) = if let Some(link_cap) = result_link.captures(block) {
            let url = link_cap[1].to_string();
            let title = html_decode(&tag.replace_all(&link_cap[2], ""));
            (url, title)
        } else {
            continue;
        };

        if !url.starts_with("http") {
            continue;
        }

        // Extract snippet from block
        let snippet = if let Some(snip_cap) = result_snippet.captures(block) {
            let raw = snip_cap.get(1).or_else(|| snip_cap.get(2));
            match raw {
                Some(m) => html_decode(&tag.replace_all(m.as_str(), "")),
                None => String::new(),
            }
        } else {
            String::new()
        };

        results.push(SearchResult {
            title,
            url,
            snippet,
        });
    }

    results
}

fn html_decode(s: &str) -> String {
    s.replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&#x27;", "'")
        .replace("&apos;", "'")
        .trim()
        .to_string()
}
