import json

with open('extracted_utf8.txt', 'r', encoding='utf-8') as f:
    text = f.read()

import re
json_blocks = []
current = ""
for line in text.splitlines():
    if line == "{":
        if current:
            json_blocks.append(current)
        current = "{\n"
    elif current:
        current += line + "\n"
if current:
    json_blocks.append(current)

# First, restore to the original git version again just to be safe
import os
os.system("git checkout android/app/src/main/cpp/native-render.cpp")

with open(r'C:\Users\gagan\Projects\retro-mesh-console\android\app\src\main\cpp\native-render.cpp', 'r', encoding='utf-8') as f:
    code = f.read().replace('\r\n', '\n')

for i, block in enumerate(json_blocks):
    try:
        data = json.loads(block)
        if "Removing AAudio Block" in data.get('toolAction', ''):
            print("Skipping erroneous patch:", data['toolAction'])
            continue
            
        print("Applying:", data['toolAction'])
        chunks = data['ReplacementChunks']
        
        # We must apply sequentially, but wait, replace() acts globally!
        # And we don't need to sort them because we are doing string replacement.
        for chunk in chunks:
            target = chunk['TargetContent'].replace('\r\n', '\n')
            replacement = chunk['ReplacementContent'].replace('\r\n', '\n')
            
            if target in code:
                code = code.replace(target, replacement)
            else:
                print("WARNING: Could not find target in chunk for", data['toolAction'])
                
    except Exception as e:
        print("Error on block", i, e)

with open(r'C:\Users\gagan\Projects\retro-mesh-console\android\app\src\main\cpp\native-render.cpp', 'w', encoding='utf-8', newline='\n') as f:
    f.write(code)

print("Done restoring native-render.cpp")
