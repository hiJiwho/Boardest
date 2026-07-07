const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";
const outPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\scratch\\step_2151_2152.txt";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  const outStream = fs.createWriteStream(outPath, { encoding: 'utf8' });

  for await (const line of rl) {
    const data = JSON.parse(line);
    if (data.step_index === 2151 || data.step_index === 2152) {
      outStream.write(`\n=========================================\n`);
      outStream.write(`STEP ${data.step_index} (Type: ${data.type}, Source: ${data.source})\n`);
      outStream.write(`=========================================\n`);
      
      if (data.content) {
        outStream.write(`--- CONTENT ---\n`);
        outStream.write(data.content + "\n");
      }
      
      if (data.tool_calls) {
        outStream.write(`--- TOOL CALLS ---\n`);
        outStream.write(JSON.stringify(data.tool_calls, null, 2) + "\n");
      }
    }
  }
  outStream.end();
  console.log("Done extracting step 2151 and 2152");
}

main().catch(err => console.error(err));
