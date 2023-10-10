import json


def minify_json(file_path: str) -> str:
    with open(file_path, "r", encoding="utf8") as file:
        data = json.load(file)
        return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


# Minify the `cap_exams.json` file to reduce its size.
if __name__ == "__main__":
    minified_data = minify_json("cap_exams.json")
    with open("cap_exams.json", "w", encoding="utf8") as f:
        f.write(minified_data)

    print("Successfully minified the `cap_exams.json` file.")
