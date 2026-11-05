import os
import json
import re

def find_matching_paren(text, start_index):
    count = 0
    for i in range(start_index, len(text)):
        if text[i] == '(':
            count += 1
        elif text[i] == ')':
            count -= 1
            if count == 0:
                return i
    return -1

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')
    chunks = []

    # Add import statement if not exists
    import_stmt = "import 'package:earanyak/widgets/animated_button_wrapper.dart';"
    if import_stmt not in content:
        last_import_line = -1
        for i, line in enumerate(lines):
            if line.startswith('import '):
                last_import_line = i

        if last_import_line != -1:
            chunks.append({
                "targetContent": lines[last_import_line],
                "replacementContent": lines[last_import_line] + "\n" + import_stmt,
                "startLine": last_import_line + 1,
                "endLine": last_import_line + 1,
                "allowMultiple": False
            })
        else:
            chunks.append({
                "targetContent": lines[0],
                "replacementContent": import_stmt + "\n" + lines[0],
                "startLine": 1,
                "endLine": 1,
                "allowMultiple": False
            })

    pattern = re.compile(r'\b(ElevatedButton|ElevatedButton\.icon|TextButton|TextButton\.icon|IconButton|IconButton\.filled)\s*\(')

    current_idx = 0
    while True:
        match = pattern.search(content, current_idx)
        if not match:
            break

        start_paren_idx = match.end() - 1
        end_paren_idx = find_matching_paren(content, start_paren_idx)

        if end_paren_idx != -1:
            start_line_idx = content.count('\n', 0, match.start())
            end_line_idx = content.count('\n', 0, end_paren_idx)

            # The start target is just the specific line containing the match
            start_line_text = lines[start_line_idx]
            match_str = match.group(0) # e.g. "ElevatedButton("

            # Replace exactly the matched string in the start line text
            start_replacement_text = start_line_text[:match.start() - sum(len(l)+1 for l in lines[:start_line_idx])] + \
                                     f"AnimatedButtonWrapper(child: {match_str}" + \
                                     start_line_text[match.end() - sum(len(l)+1 for l in lines[:start_line_idx]):]

            # Actually, to be simpler and safer, targetContent is the exact original line,
            # and replacementContent is that line with AnimatedButtonWrapper(child: added.
            # But what if there are multiple matches on the same line?
            # It's better to just do string replacement on the line.

            line_start_char_idx = sum(len(l)+1 for l in lines[:start_line_idx])
            local_start = match.start() - line_start_char_idx
            local_end = match.end() - line_start_char_idx

            new_start_line_text = start_line_text[:local_start] + f"AnimatedButtonWrapper(child: {match_str}" + start_line_text[local_end:]

            chunks.append({
                "targetContent": start_line_text,
                "replacementContent": new_start_line_text,
                "startLine": start_line_idx + 1,
                "endLine": start_line_idx + 1,
                "allowMultiple": False # it's possible it fails if there are duplicate identical lines, but startLine/endLine is specific
            })

            # Now the end parenthesis
            end_line_text = lines[end_line_idx]
            line_end_char_idx = sum(len(l)+1 for l in lines[:end_line_idx])
            local_end_paren = end_paren_idx - line_end_char_idx

            new_end_line_text = end_line_text[:local_end_paren] + "))" + end_line_text[local_end_paren+1:]

            chunks.append({
                "targetContent": end_line_text,
                "replacementContent": new_end_line_text,
                "startLine": end_line_idx + 1,
                "endLine": end_line_idx + 1,
                "allowMultiple": False
            })

            # Note: We must be careful if start and end are on the same line.
            if start_line_idx == end_line_idx:
                # We need to combine them into one chunk
                chunks.pop()
                chunks.pop()

                single_line_text = start_line_text
                new_single_line = single_line_text[:local_start] + f"AnimatedButtonWrapper(child: {match_str}" + single_line_text[local_end:local_end_paren] + "))" + single_line_text[local_end_paren+1:]
                chunks.append({
                    "targetContent": single_line_text,
                    "replacementContent": new_single_line,
                    "startLine": start_line_idx + 1,
                    "endLine": start_line_idx + 1,
                    "allowMultiple": False
                })

            current_idx = end_paren_idx + 1
        else:
            current_idx = match.end()

    return chunks

files = []
for root, dirs, filenames in os.walk('lib/screens'):
    for f in filenames:
        if f.endswith('.dart'):
            files.append(os.path.join(root, f))
for root, dirs, filenames in os.walk('lib/widgets'):
    for f in filenames:
        if f.endswith('.dart'):
            files.append(os.path.join(root, f))

result = {}
for f in files:
    try:
        chunks = process_file(f)
        if len(chunks) > 1 or (len(chunks) == 1 and not chunks[0]['replacementContent'].startswith("import ")):
            result[f.replace('\\\\', '/')] = chunks
    except Exception as e:
        print(f"Error in {f}: {e}")

with open('refactoring_tool_calls.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)

print("Done. Saved to refactoring_tool_calls.json")
