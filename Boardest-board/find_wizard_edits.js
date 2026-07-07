const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";
const outPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\scratch\\wizard_file_steps.txt";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  const outStream = fs.createWriteStream(outPath, { encoding: 'utf8' });

  for await (const line of rl) {
    const data = JSON.parse(line);
    const tcStr = JSON.stringify(data.tool_calls || []);
    if (tcStr.includes("setup_wizard_view.dart")) {
      outStream.write(`Step ${data.step_index}: Type = ${data.type}, Source = ${data.source}\n`);
      for (const tc of (data.tool_calls || [])) {
        if (tc.name === 'view_file' || tc.name === 'replace_file_content' || tc.name === 'write_to_file' || tc.name === 'multi_replace_file_content') {
          outStream.write(`  Tool Call: ${tc.name}\n`);
          if (tc.args) {
            outStream.write(`    StartLine: ${tc.args.StartLine}, EndLine: ${tc.args.EndLine}\n`);
            if (tc.args.TargetContent) {
              outStream.write(`    TargetContent length: ${tc.args.TargetContent.length}\n`);
            }
            if (tc.args.ReplacementContent) {
              outStream.write(`    ReplacementContent length: ${tc.args.ReplacementContent.length}\n`);
            }
          }
        }
      }
      
      // If it has output content that contains setup_wizard_view.dart (e.g. view_file output)
      if (data.content && data.content.includes("setup_wizard_view.dart")) {
        outStream.write(`  Content has setup_wizard_view.dart, length: ${data.content.length}\n`);
      }
    }
  }
  outStream.end();
  console.log("Done scanning wizard file steps");
}

main().catch(err => console.error(err));
