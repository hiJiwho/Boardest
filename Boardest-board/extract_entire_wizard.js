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
    const toolCalls = data.tool_calls || [];
    for (const tc of toolCalls) {
      const tcStr = JSON.stringify(tc);
      if (tcStr.toLowerCase().includes("setup_wizard_view.dart")) {
        let len = 0;
        if (tc.args) {
          if (tc.args.CodeContent) len = tc.args.CodeContent.length;
          else if (tc.args.ReplacementContent) len = tc.args.ReplacementContent.length;
        }
        console.log(`Step ${data.step_index}: Tool=${tc.name}, Len=${len}, Path=${tc.args ? tc.args.TargetFile : 'n/a'}`);
      }
    }
  }
}

main().catch(err => console.error(err));
