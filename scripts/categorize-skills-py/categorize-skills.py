#!/usr/bin/env python3
import os
import re
import shutil

SKILLS_DIR = '/home/zhanxp/projects/myagent/skills/skills-download'
METADATA_PATTERN = re.compile(r'^---\n([\s\S]*?)\n---', re.MULTILINE)
AUTHOR_PATTERN = re.compile(r'^\s*author:\s*(.+)$', re.MULTILINE | re.IGNORECASE)

def extract_author(skill_path):
    skill_md_path = os.path.join(skill_path, 'SKILL.md')
    if not os.path.exists(skill_md_path):
        return None
    
    try:
        with open(skill_md_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        metadata_match = METADATA_PATTERN.search(content)
        if metadata_match:
            yaml = metadata_match.group(1)
            author_match = AUTHOR_PATTERN.search(yaml)
            if author_match:
                return author_match.group(1).strip()
    except Exception as e:
        print(f"Error reading {skill_md_path}: {e}")
    return None

def main():
    print("Categorizing skills...")
    print("=" * 50)
    
    categories = {}
    uncategorized = []
    
    # Get all skill directories
    dirs = [d for d in os.listdir(SKILLS_DIR) if os.path.isdir(os.path.join(SKILLS_DIR, d)) and not d.startswith('.')]
    
    for dir_name in dirs:
        full_path = os.path.join(SKILLS_DIR, dir_name)
        author = extract_author(full_path)
        
        if author:
            if author not in categories:
                categories[author] = []
            categories[author].append(dir_name)
            print(f"{dir_name:<30} -> {author}")
        else:
            uncategorized.append(dir_name)
            print(f"{dir_name:<30} -> <uncategorized>")
    
    # Create category directories and move skills
    print("\nCreating category directories...")
    print("=" * 50)
    
    for category in categories:
        category_dir = os.path.join(SKILLS_DIR, category)
        if not os.path.exists(category_dir):
            os.makedirs(category_dir, exist_ok=True)
            print(f"Created category: {category}")
        
        for skill in categories[category]:
            src = os.path.join(SKILLS_DIR, skill)
            dest = os.path.join(category_dir, skill)
            
            if os.path.exists(dest):
                print(f"Warning: {dest} already exists, skipping {skill}")
                continue
            
            shutil.move(src, dest)
            print(f"Moved: {skill} -> {category}/")
    
    if uncategorized:
        print("\n" + "=" * 50)
        print(f"Uncategorized skills ({len(uncategorized)}):")
        for skill in uncategorized:
            print(f"- {skill}")
    
    print("\nDone!")

if __name__ == '__main__':
    main()
