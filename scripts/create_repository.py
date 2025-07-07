import json
import os

def generate_core_json(modstxt, output_dir):
    mods = []
    
    special_install_types = {
        "lovely": "lovely_prebuilt",
        "steamodded": "smods_prebuilt",
    }

    try:
        with open(modstxt, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue

                parts = [p.strip() for p in line.split('|')]
                
                if len(parts) < 4:
                    print(f"[WARNING] Skipping malformed line (less than 4 parts): {line}")
                    continue

                name = parts[0]
                download_url = parts[1]
                dependencies_str = parts[2]
                category = parts[3]

                dependencies = [dep.strip() for dep in dependencies_str.split(',') if dep.strip()]

                install_type = special_install_types.get(name.lower())
                if not install_type:
                    if download_url.endswith('.git'):
                        install_type = 'git'
                    else:
                        install_type = 'zip' 

                mod_entry = {
                    "name": name,
                    "download_url": download_url,
                    "dependencies": dependencies,
                    "category": category,
                    "install_type": install_type
                }
                mods.append(mod_entry)

    except FileNotFoundError:
        print(f"[ERROR] mods.txt not found at {mods_txt_path}. Please ensure it exists.")
        return

    repo_data = {
        "name": "",
        "author": "",
        "description": "",
        "url": "",
        "mods": mods
    }

    output_file = os.path.join(output_dir, ".json")
    
    os.makedirs(output_dir, exist_ok=True)

    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(repo_data, f, indent=2)
        print(f"[INFO] Successfully created {output_file} with {len(mods)} mods.")
    except IOError as e:
        print(f"[ERROR] Error writing to file {output_file}: {e}")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    modstxt = os.path.join(script_dir, "mods.txt")
    
    out = os.path.expanduser(".") 

    generate_core_json(modstxt, out)
