const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";
const outPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\scratch\\step_2053_details.txt";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  const outStream = fs.createWriteStream(outPath, { encoding: 'utf8' });

  for await (const line of rl) {
    const data = JSON.parse(line);
    if (data.step_index === 2053) {
      outStream.write(`=== STEP 2053 ===\n`);
      const tc = data.tool_calls && data.tool_calls[0];
      if (tc) {
        outStream.write(`Tool Call: ${tc.name}\n`);
        outStream.write(`Arguments:\n`);
        outStream.write(JSON.stringify(tc.args, null, 2));
      }
      break;
    }
  }
  outStream.end();
  console.log("Done extracting step 2053 details");
}

main().catch(err => console.error(err));
