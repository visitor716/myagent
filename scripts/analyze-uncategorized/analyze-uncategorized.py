#!/usr/bin/env python3
import os
import re
import yaml

SKILLS_DIR = '/home/zhanxp/projects/myagent/skills/skills-download'
METADATA_PATTERN = re.compile(r'^---\n([\s\S]*?)\n---', re.MULTILINE)

def extract_metadata(skill_path):
    skill_md_path = os.path.join(skill_path, 'SKILL.md')
    if not os.path.exists(skill_md_path):
        return None
    
    try:
        with open(skill_md_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        metadata_match = METADATA_PATTERN.search(content)
        if metadata_match:
            yaml_str = metadata_match.group(1)
            return yaml.safe_load(yaml_str)
    except Exception as e:
        print(f"Error reading {skill_md_path}: {e}")
    return None

def main():
    print("=" * 100)
    print("Uncategorized Skills - Detailed Info")
    print("=" * 100)
    
    # Get all remaining skill directories
    dirs = [d for d in os.listdir(SKILLS_DIR) 
            if os.path.isdir(os.path.join(SKILLS_DIR, d)) 
            and not d.startswith('.')
            and d != 'vercel']
    
    for dir_name in sorted(dirs):
        print(f"\n--- {dir_name} ---")
        full_path = os.path.join(SKILLS_DIR, dir_name)
        metadata = extract_metadata(full_path)
        
        if metadata:
            print(f"Name: {metadata.get('name', '<unknown>')}")
            print(f"Description: {metadata.get('description', '<unknown>')}")
            if 'metadata' in metadata:
                for key, value in metadata['metadata'].items():
                    print(f"{key}: {value}")
        else:
            print("No metadata found")

if __name__ == '__main__':
    main()
