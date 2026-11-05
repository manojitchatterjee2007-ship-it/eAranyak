import json
import os

with open('refactoring_tool_calls.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

files = list(data.keys())
calls = []
for filepath in files:
    chunks = data[filepath]
    call_dict = {
        "absolutePath": os.path.abspath(filepath).replace('\\', '/'),
        "replacementChunks": chunks
    }
    calls.append(f"\\N\u200Dcall:default_api:multi_replace_file_content{json.dumps(call_dict)}\\N\u200D")

with open('calls.txt', 'w', encoding='utf-8') as f:
    f.write("".join(calls).replace("\\N\u200D", "\n\n"))
