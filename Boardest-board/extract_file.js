const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";
const outPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\scratch\\restored_setup_wizard_view.dart";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  const stepsToExtract = [1713, 1715, 1721, 1725, 1727, 1731];
  const contents = {};

  for await (const line of rl) {
    const data = JSON.parse(line);
    if (stepsToExtract.includes(data.step_index)) {
      if (data.content) {
        contents[data.step_index] = data.content;
      }
    }
  }

  const outStream = fs.createWriteStream(outPath, { encoding: 'utf8' });

  const allLines = {};

  for (const step of stepsToExtract) {
    const content = contents[step];
    if (!content) {
      console.log(`Warning: No content found for step ${step}`);
      continue;
    }
    const lines = content.split('\n');
    for (const line of lines) {
      const match = line.match(/^(\d+): (.*)$/);
      if (match) {
        const lineNum = parseInt(match[1], 10);
        const originalLine = match[2];
        allLines[lineNum] = originalLine;
      }
    }
  }

  const sortedLineNums = Object.keys(allLines).map(Number).sort((a, b) => a - b);
  console.log(`Found ${sortedLineNums.length} lines. Range: ${sortedLineNums[0]} to ${sortedLineNums[sortedLineNums.length - 1]}`);

  for (const num of sortedLineNums) {
    outStream.write(allLines[num] + '\n');
  }

  outStream.end();
  console.log("Done restoring setup_wizard_view.dart");
}

main().catch(err => console.error(err));
