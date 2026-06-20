#!/usr/bin/env node

import * as fs from 'fs';
import * as path from 'path';

const SKILLS_DIR = path.join(__dirname, '../skills/skills-download');
const METADATA_SECTION_REGEX = /^---\n([\s\S]*?)\n---/;
const AUTHOR_REGEX = /author:\s*(.+)/;

function extractAuthor(skillPath: string): string | null {
  const skillMdPath = path.join(skillPath, 'SKILL.md');
  if (!fs.existsSync(skillMdPath)) return null;
  
  try {
    const content = fs.readFileSync(skillMdPath, 'utf-8');
    const match = content.match(METADATA_SECTION_REGEX);
    if (match) {
      const yaml = match[1];
      const authorMatch = yaml.match(AUTHOR_REGEX);
      if (authorMatch) {
        return authorMatch[1].trim();
      }
    }
  } catch (e) {
    console.error(`Error reading ${skillMdPath}:`, e);
  }
  return null;
}

function main() {
  console.log('Categorizing skills...');
  
  const categories: Record<string, string[]> = {};
  const uncategorized: string[] = [];
  
  const dirs = fs.readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter(dirent => dirent.isDirectory() && !dirent.name.startsWith('.'))
    .map(dirent => dirent.name);
  
  for (const dir of dirs) {
    const fullPath = path.join(SKILLS_DIR, dir);
    const author = extractAuthor(fullPath);
    
    if (author) {
      if (!categories[author]) {
        categories[author] = [];
      }
      categories[author].push(dir);
      console.log(`${dir} -> ${author}`);
    } else {
      uncategorized.push(dir);
      console.log(`${dir} -> <uncategorized>`);
    }
  }
  
  // Create category directories
  console.log('\nCreating category directories...');
  for (const category of Object.keys(categories)) {
    const categoryDir = path.join(SKILLS_DIR, category);
    if (!fs.existsSync(categoryDir)) {
      fs.mkdirSync(categoryDir, { recursive: true });
      console.log(`Created: ${categoryDir}`);
    }
    
    // Move skills to category directories
    for (const skill of categories[category]) {
      const src = path.join(SKILLS_DIR, skill);
      const dest = path.join(SKILLS_DIR, category, skill);
      
      if (!fs.existsSync(dest)) {
        fs.renameSync(src, dest);
        console.log(`Moved: ${skill} -> ${category}/`);
      }
    }
  }
  
  if (uncategorized.length > 0) {
    console.log('\nUncategorized skills:');
    for (const skill of uncategorized) {
      console.log(`- ${skill}`);
    }
  }
  
  console.log('\nDone!');
}

main();
