import json
import sys
import os

batch_idx = int(sys.argv[1])
batch_size = 10

with open('refactoring_tool_calls.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

files = list(data.keys())
start = batch_idx * batch_size
end = min(start + batch_size, len(files))

batch_files = files[start:end]
calls = []
for filepath in batch_files:
    call_dict = {
        "absolutePath": os.path.abspath(filepath).replace('\\', '/'),
        "replacementChunks": data[filepath]
    }
    s = f"call:default_api:multi_replace_file_content{json.dumps(call_dict)}"
    calls.append(s)

with open('current_batch.txt', 'w', encoding='utf-8') as f:
    f.write("\n".join(calls))

print(f"Batch {batch_idx}: {len(batch_files)} files.")
