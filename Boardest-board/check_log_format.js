const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  for await (const line of rl) {
    const data = JSON.parse(line);
    if (data.step_index >= 1710 && data.step_index <= 1735) {
      console.log(`Step ${data.step_index}: type=${data.type}, source=${data.source}, keys=${Object.keys(data).join(',')}`);
      if (data.tool_calls) {
        console.log(`  tool_calls: ${JSON.stringify(data.tool_calls)}`);
      }
      if (data.content && data.content.length > 0) {
        console.log(`  content length: ${data.content.length}, starts with: ${data.content.substring(0, 100).replace(/\n/g, '\\n')}`);
      }
    }
  }
}

main().catch(err => console.error(err));
