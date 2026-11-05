import json
import os

with open('refactoring_tool_calls.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

files = list(data.keys())

for i, filepath in enumerate(files):
    call_dict = {
        "absolutePath": os.path.abspath(filepath).replace('\\', '/'),
        "replacementChunks": data[filepath]
    }
    with open(f'calls_batch_{i}.txt', 'w', encoding='utf-8') as f:
        # pretty print json to make it readable in chunks, BUT the tool call format expects compact
        # Wait, if I do `json.dumps(call_dict)` it's compact. But it hits output limit in read_file if it's too long on one line.
        # But `replace_file_content` supports multiline JSON if it's within the `{}`.
        s = f"call:default_api:multi_replace_file_content{json.dumps(call_dict)}"
        f.write(s)
