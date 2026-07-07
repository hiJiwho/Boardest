const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";
const outPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\scratch\\extracted_steps_details.txt";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  const steps = [452, 464, 1040, 1083, 1186, 1725, 1818, 1822];
  const outStream = fs.createWriteStream(outPath, { encoding: 'utf8' });

  for await (const line of rl) {
    const data = JSON.parse(line);
    if (steps.includes(data.step_index)) {
      outStream.write(`\n=========================================\n`);
      outStream.write(`STEP ${data.step_index} (Type: ${data.type}, Source: ${data.source})\n`);
      outStream.write(`=========================================\n`);
      
      if (data.content) {
        outStream.write(`--- CONTENT (length: ${data.content.length}) ---\n`);
        outStream.write(data.content + "\n");
      }
      
      if (data.tool_calls) {
        outStream.write(`--- TOOL CALLS ---\n`);
        outStream.write(JSON.stringify(data.tool_calls, null, 2) + "\n");
      }
    }
  }
  outStream.end();
  console.log("Done extracting steps details");
}

main().catch(err => console.error(err));
