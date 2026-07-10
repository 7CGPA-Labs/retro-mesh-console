import json
import re

output_lines = []
with open(r'C:\Users\gagan\.gemini\antigravity\brain\1dbc06ad-6989-4251-a8b7-4c4fe06a880b\.system_generated\logs\transcript_full.jsonl', 'r', encoding='utf-8') as f:
    for line in f:
        if 'native-render.cpp' in line and 'ReplacementChunks' in line:
            try:
                data = json.loads(line)
                for tc in data.get('tool_calls', []):
                    if tc['name'] == 'multi_replace_file_content':
                        args = tc['args']
                        if 'native-render.cpp' in args.get('TargetFile', ''):
                            output_lines.append(json.dumps(args, indent=2))
            except Exception as e:
                pass

with open('extracted_utf8.txt', 'w', encoding='utf-8') as f:
    f.write('\n'.join(output_lines))
