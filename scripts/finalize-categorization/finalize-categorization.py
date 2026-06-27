#!/usr/bin/env python3
import os
import shutil

SKILLS_DIR = '/home/zhanxp/projects/myagent/skills/skills-download'

def main():
    # Define categorization
    categories = {
        'opencli': [
            'opencli-adapter-author',
            'opencli-autofix',
            'opencli-browser',
            'opencli-usage'
        ],
        'omx': [
            'ai-slop-cleaner',
            'code-review',
            'security-review'
        ],
        'personal-tools': [
            'agent-usage-monitor',
            'coding-standards',
            'find-docs',
            'find-skills',
            'wx-cli'
        ]
    }
    
    print("Creating additional categories...")
    print("=" * 50)
    
    for category, skills in categories.items():
        category_dir = os.path.join(SKILLS_DIR, category)
        if not os.path.exists(category_dir):
            os.makedirs(category_dir, exist_ok=True)
            print(f"Created category: {category}")
        
        for skill in skills:
            src = os.path.join(SKILLS_DIR, skill)
            dest = os.path.join(category_dir, skill)
            
            if not os.path.exists(src):
                continue
            
            if os.path.exists(dest):
                print(f"Warning: {dest} already exists, skipping {skill}")
                continue
            
            shutil.move(src, dest)
            print(f"Moved: {skill} -> {category}/")
    
    print("\nDone!")
    
    # Final status
    print("\nFinal directory structure:")
    print("=" * 50)
    for item in sorted(os.listdir(SKILLS_DIR)):
        item_path = os.path.join(SKILLS_DIR, item)
        if os.path.isdir(item_path) and not item.startswith('.'):
            subitems = [sub for sub in os.listdir(item_path) 
                        if os.path.isdir(os.path.join(item_path, sub)) and not sub.startswith('.')]
            print(f"{item}/ ({len(subitems)} skills)")

if __name__ == '__main__':
    main()
