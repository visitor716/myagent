#!/usr/bin/env python3
"""
技能使用情况盘点脚本
生成 HTML + CSV 报表，分析技能的安装位置、触发统计、历史使用情况
"""

import json
import os
import csv
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any


class SkillUsageAudit:
    def __init__(self):
        # 数据源路径
        self.trigger_stats_path = Path.home() / ".local" / "state" / "myagent" / "skill-trigger-stats.json"
        self.codex_skills_path = Path.home() / ".codex" / "skills"
        self.agents_skills_path = Path.home() / ".agents" / "skills"
        self.myagent_skills_path = Path("/home/zhanxp/projects/myagent/skills")
        self.memory_path = Path.home() / ".codex" / "memories" / "MEMORY.md"
        
        # 输出路径
        self.output_html = self.myagent_skills_path / "skill-usage-audit.html"
        self.output_csv = self.myagent_skills_path / "skill-usage-audit.csv"
        
        # 核心技能列表（keep-hot）
        self.core_hot_skills = {
            "my-workflows",
            "my-worktree-merge-master",
            "my-wsl-windows-chrome",
            "my-tg-webapp-url-monitor",
            "my-codex-workfolws",
            "my-merge-worktree-master",
            "my-sync-shared-skills"
        }
        
        # keep-on-demand 技能
        self.on_demand_skills = {
            "my-daily-report-table",
            "my-oa-exception-record-filler",
            "webapp-testing",
            "my-personal-bookkeeping",
            "my-reimbursement-screenshot-organizer",
            "my-tmux-manager",
            "my-windows-system-settings",
            "my-clash-proxy",
            "my-cc-connect-bot-setup"
        }
        
        # review 技能（安全/敏感）
        self.review_skills = {
            "godmode",
            "opencli-adapter-author",
            "opencli-autofix",
            "opencli-browser",
            "opencli-usage"
        }
        
        self.trigger_stats: Dict[str, Any] = {}
        self.memory_content: str = ""
        self.all_skills: Dict[str, Dict[str, Any]] = {}
        
    def load_trigger_stats(self):
        """加载触发统计数据"""
        if self.trigger_stats_path.exists():
            with open(self.trigger_stats_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                self.trigger_stats = data.get("skills", {})
    
    def load_memory(self):
        """加载记忆文件"""
        if self.memory_path.exists():
            with open(self.memory_path, 'r', encoding='utf-8') as f:
                self.memory_content = f.read()
    
    def scan_skills(self):
        """扫描所有技能安装位置"""
        # 扫描 Hermes 技能
        hermes_skills_path = Path.home() / ".hermes" / "skills"
        if hermes_skills_path.exists():
            for category_dir in hermes_skills_path.iterdir():
                if category_dir.is_dir() and not category_dir.name.startswith('.'):
                    self._scan_skill_directory(category_dir, "hermes", category_dir.name)
        
        # 扫描 Codex 技能
        if self.codex_skills_path.exists():
            self._scan_skill_directory(self.codex_skills_path, "codex", "codex")
        
        # 扫描 Agents 技能
        if self.agents_skills_path.exists():
            self._scan_skill_directory(self.agents_skills_path, "agents", "agents")
        
        # 扫描 myagent repo 技能
        if self.myagent_skills_path.exists():
            skills_download = self.myagent_skills_path / "skills-download"
            skills_local = self.myagent_skills_path / "skills-local"
            
            if skills_download.exists():
                self._scan_skill_directory(skills_download, "myagent-download", "myagent-download")
            
            if skills_local.exists():
                self._scan_skill_directory(skills_local, "myagent-local", "myagent-local")
    
    def _scan_skill_directory(self, dir_path: Path, source_root: str, category: str):
        """扫描单个技能目录"""
        for skill_dir in dir_path.iterdir():
            if not skill_dir.is_dir() or skill_dir.name.startswith('.'):
                continue
            
            # 处理符号链接
            if skill_dir.is_symlink():
                real_path = skill_dir.resolve()
                if not real_path.exists() or not real_path.is_dir():
                    continue
                skill_dir = real_path
            
            skill_name = skill_dir.name
            
            # 标准化技能名（去掉前缀）
            normalized_name = skill_name
            if normalized_name.startswith("my-"):
                normalized_name = normalized_name
            elif normalized_name.startswith("claude-") or normalized_name.startswith("codex-"):
                normalized_name = normalized_name
            
            if normalized_name not in self.all_skills:
                self.all_skills[normalized_name] = {
                    "skill_name": normalized_name,
                    "original_name": skill_name,
                    "category": category,
                    "source_root": source_root,
                    "installed_in_codex": False,
                    "installed_in_claude_or_agents": False,
                    "installed_in_myagent": False,
                    "trigger_count": 0,
                    "first_triggered_at": "",
                    "last_triggered_at": "",
                    "memory_hits": 0,
                    "status": "no-evidence",
                    "recommendation": "archive-or-disable"
                }
            
            # 标记安装位置
            if source_root == "codex":
                self.all_skills[normalized_name]["installed_in_codex"] = True
            elif source_root in ["agents", "hermes"]:
                self.all_skills[normalized_name]["installed_in_claude_or_agents"] = True
            elif source_root in ["myagent-download", "myagent-local"]:
                self.all_skills[normalized_name]["installed_in_myagent"] = True
    
    def analyze_skill(self, skill_name: str, skill_data: Dict[str, Any]):
        """分析单个技能"""
        # 检查触发统计（尝试各种可能的名称变体）
        possible_names = [
            skill_name,
            skill_data["original_name"],
            f"my-{skill_name}" if not skill_name.startswith("my-") else skill_name.replace("my-", ""),
            skill_name.replace("my-", ""),
        ]
        
        trigger_info = None
        for name in possible_names:
            if name in self.trigger_stats:
                trigger_info = self.trigger_stats[name]
                break
        
        if trigger_info:
            skill_data["trigger_count"] = trigger_info.get("total", 0)
            skill_data["first_triggered_at"] = trigger_info.get("first_triggered_at", "")
            skill_data["last_triggered_at"] = trigger_info.get("last_triggered_at", "")
        
        # 检查记忆命中
        skill_data["memory_hits"] = self.memory_content.lower().count(skill_name.lower())
        skill_data["memory_hits"] += self.memory_content.lower().count(skill_data["original_name"].lower())
        
        # 确定状态
        if skill_data["trigger_count"] > 0:
            skill_data["status"] = "used"
        elif skill_data["memory_hits"] > 0:
            skill_data["status"] = "memory-only"
        else:
            skill_data["status"] = "no-evidence"
        
        # 确定建议
        if skill_name in self.review_skills or skill_data["original_name"] in self.review_skills:
            skill_data["recommendation"] = "review"
        elif skill_name in self.core_hot_skills or skill_data["original_name"] in self.core_hot_skills:
            skill_data["recommendation"] = "keep-hot"
        elif skill_name in self.on_demand_skills or skill_data["original_name"] in self.on_demand_skills:
            skill_data["recommendation"] = "keep-on-demand"
        elif skill_data["status"] == "memory-only":
            skill_data["recommendation"] = "keep-on-demand"
        elif skill_data["trigger_count"] > 0:
            skill_data["recommendation"] = "keep-hot" if skill_data["trigger_count"] >= 5 else "keep-on-demand"
        else:
            skill_data["recommendation"] = "archive-or-disable"
    
    def generate_csv(self, skills_list: List[Dict[str, Any]]):
        """生成 CSV 报表"""
        fieldnames = [
            "skill_name",
            "category",
            "source_root",
            "installed_in_codex",
            "installed_in_claude_or_agents",
            "installed_in_myagent",
            "trigger_count",
            "first_triggered_at",
            "last_triggered_at",
            "memory_hits",
            "status",
            "recommendation"
        ]
        
        with open(self.output_csv, 'w', encoding='utf-8-sig', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            
            for skill in skills_list:
                writer.writerow({k: skill.get(k, "") for k in fieldnames})
        
        print(f"✅ CSV 报表已生成: {self.output_csv}")
    
    def generate_html(self, skills_list: List[Dict[str, Any]]):
        """生成 HTML 报表"""
        # 统计汇总
        total_skills = len(skills_list)
        used_skills = sum(1 for s in skills_list if s["status"] == "used")
        memory_only = sum(1 for s in skills_list if s["status"] == "memory-only")
        no_evidence = sum(1 for s in skills_list if s["status"] == "no-evidence")
        
        keep_hot = sum(1 for s in skills_list if s["recommendation"] == "keep-hot")
        keep_on_demand = sum(1 for s in skills_list if s["recommendation"] == "keep-on-demand")
        archive = sum(1 for s in skills_list if s["recommendation"] == "archive-or-disable")
        review = sum(1 for s in skills_list if s["recommendation"] == "review")
        
        html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>技能使用情况盘点报表</title>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; padding: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1400px; margin: 0 auto; background: white; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; }}
        .header h1 {{ font-size: 28px; margin-bottom: 10px; }}
        .header p {{ opacity: 0.9; }}
        .summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; padding: 30px; background: #fafafa; border-bottom: 1px solid #eee; }}
        .stat-card {{ background: white; padding: 20px; border-radius: 8px; text-align: center; border: 1px solid #eee; }}
        .stat-card .number {{ font-size: 36px; font-weight: bold; margin-bottom: 5px; }}
        .stat-card .label {{ color: #666; font-size: 14px; }}
        .number.keep-hot {{ color: #10b981; }}
        .number.keep-on-demand {{ color: #f59e0b; }}
        .number.archive {{ color: #ef4444; }}
        .number.review {{ color: #8b5cf6; }}
        .filters {{ padding: 20px 30px; border-bottom: 1px solid #eee; display: flex; flex-wrap: wrap; gap: 15px; align-items: center; }}
        .filter-group {{ display: flex; align-items: center; gap: 8px; }}
        .filter-group label {{ font-weight: 500; color: #333; }}
        .filter-group select, .filter-group input {{ padding: 8px 12px; border: 1px solid #ddd; border-radius: 6px; font-size: 14px; }}
        .table-container {{ padding: 30px; overflow-x: auto; }}
        table {{ width: 100%; border-collapse: collapse; font-size: 14px; }}
        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #eee; }}
        th {{ background: #f8f9fa; font-weight: 600; color: #333; position: sticky; top: 0; cursor: pointer; }}
        th:hover {{ background: #e9ecef; }}
        tr:hover {{ background: #f8f9fa; }}
        .status-badge {{ padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 500; display: inline-block; }}
        .status-used {{ background: #d1fae5; color: #065f46; }}
        .status-memory-only {{ background: #fef3c7; color: #92400e; }}
        .status-no-evidence {{ background: #f3f4f6; color: #4b5563; }}
        .rec-badge {{ padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 500; display: inline-block; }}
        .rec-keep-hot {{ background: #d1fae5; color: #065f46; }}
        .rec-keep-on-demand {{ background: #fef3c7; color: #92400e; }}
        .rec-archive {{ background: #fee2e2; color: #991b1b; }}
        .rec-review {{ background: #ede9fe; color: #5b21b6; }}
        .hidden {{ display: none; }}
        .footer {{ padding: 20px 30px; text-align: center; color: #666; font-size: 13px; border-top: 1px solid #eee; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔧 技能使用情况盘点报表</h1>
            <p>生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
        
        <div class="summary">
            <div class="stat-card">
                <div class="number">{total_skills}</div>
                <div class="label">总技能数</div>
            </div>
            <div class="stat-card">
                <div class="number status-used">{used_skills}</div>
                <div class="label">已使用技能</div>
            </div>
            <div class="stat-card">
                <div class="number status-memory-only">{memory_only}</div>
                <div class="label">仅记忆命中</div>
            </div>
            <div class="stat-card">
                <div class="number status-no-evidence">{no_evidence}</div>
                <div class="label">无使用证据</div>
            </div>
            <div class="stat-card">
                <div class="number keep-hot">{keep_hot}</div>
                <div class="label">建议保留-核心</div>
            </div>
            <div class="stat-card">
                <div class="number keep-on-demand">{keep_on_demand}</div>
                <div class="label">建议保留-按需</div>
            </div>
            <div class="stat-card">
                <div class="number archive">{archive}</div>
                <div class="label">建议归档</div>
            </div>
            <div class="stat-card">
                <div class="number review">{review}</div>
                <div class="label">需要审核</div>
            </div>
        </div>
        
        <div class="filters">
            <div class="filter-group">
                <label>状态:</label>
                <select id="statusFilter">
                    <option value="">全部</option>
                    <option value="used">已使用</option>
                    <option value="memory-only">仅记忆命中</option>
                    <option value="no-evidence">无使用证据</option>
                </select>
            </div>
            <div class="filter-group">
                <label>建议:</label>
                <select id="recommendationFilter">
                    <option value="">全部</option>
                    <option value="keep-hot">保留-核心</option>
                    <option value="keep-on-demand">保留-按需</option>
                    <option value="archive-or-disable">归档或禁用</option>
                    <option value="review">需要审核</option>
                </select>
            </div>
            <div class="filter-group">
                <label>搜索:</label>
                <input type="text" id="searchInput" placeholder="搜索技能名...">
            </div>
        </div>
        
        <div class="table-container">
            <table id="skillsTable">
                <thead>
                    <tr>
                        <th>技能名</th>
                        <th>分类</th>
                        <th>Codex</th>
                        <th>Agents/Hermes</th>
                        <th>MyAgent</th>
                        <th>触发次数</th>
                        <th>首次触发</th>
                        <th>最近触发</th>
                        <th>记忆命中</th>
                        <th>状态</th>
                        <th>建议</th>
                    </tr>
                </thead>
                <tbody id="tableBody">
"""
        
        # 生成表格行
        for skill in skills_list:
            status_class = f"status-{skill['status']}"
            rec_class = f"rec-{skill['recommendation']}"
            status_text = {
                "used": "已使用",
                "memory-only": "仅记忆命中",
                "no-evidence": "无使用证据"
            }.get(skill["status"], skill["status"])
            
            rec_text = {
                "keep-hot": "保留-核心",
                "keep-on-demand": "保留-按需",
                "archive-or-disable": "归档或禁用",
                "review": "需要审核"
            }.get(skill["recommendation"], skill["recommendation"])
            
            html += f"""
                    <tr data-status="{skill['status']}" data-recommendation="{skill['recommendation']}">
                        <td><strong>{skill['skill_name']}</strong></td>
                        <td>{skill['category']}</td>
                        <td>{'✓' if skill['installed_in_codex'] else ''}</td>
                        <td>{'✓' if skill['installed_in_claude_or_agents'] else ''}</td>
                        <td>{'✓' if skill['installed_in_myagent'] else ''}</td>
                        <td>{skill['trigger_count']}</td>
                        <td>{skill['first_triggered_at'][:10] if skill['first_triggered_at'] else ''}</td>
                        <td>{skill['last_triggered_at'][:10] if skill['last_triggered_at'] else ''}</td>
                        <td>{skill['memory_hits']}</td>
                        <td><span class="status-badge {status_class}">{status_text}</span></td>
                        <td><span class="rec-badge {rec_class}">{rec_text}</span></td>
                    </tr>
"""
        
        html += """
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>报表说明: 本表基于本机触发统计和记忆文件生成，不代表全局使用情况</p>
        </div>
    </div>
    
    <script>
        // 过滤功能
        const statusFilter = document.getElementById('statusFilter');
        const recommendationFilter = document.getElementById('recommendationFilter');
        const searchInput = document.getElementById('searchInput');
        const tableBody = document.getElementById('tableBody');
        const rows = tableBody.querySelectorAll('tr');
        
        function applyFilters() {
            const statusValue = statusFilter.value;
            const recValue = recommendationFilter.value;
            const searchValue = searchInput.value.toLowerCase();
            
            rows.forEach(row => {
                const rowStatus = row.dataset.status;
                const rowRec = row.dataset.recommendation;
                const rowText = row.textContent.toLowerCase();
                
                const statusMatch = !statusValue || rowStatus === statusValue;
                const recMatch = !recValue || rowRec === recValue;
                const searchMatch = !searchValue || rowText.includes(searchValue);
                
                if (statusMatch && recMatch && searchMatch) {
                    row.classList.remove('hidden');
                } else {
                    row.classList.add('hidden');
                }
            });
        }
        
        statusFilter.addEventListener('change', applyFilters);
        recommendationFilter.addEventListener('change', applyFilters);
        searchInput.addEventListener('input', applyFilters);
        
        // 排序功能
        const table = document.getElementById('skillsTable');
        const headers = table.querySelectorAll('th');
        let sortDirection = {};
        
        headers.forEach((header, index) => {
            header.addEventListener('click', () => {
                const key = index;
                sortDirection[key] = !sortDirection[key];
                
                const rowsArray = Array.from(rows);
                rowsArray.sort((a, b) => {
                    const aVal = a.cells[index].textContent.trim();
                    const bVal = b.cells[index].textContent.trim();
                    
                    // 数字排序
                    if (!isNaN(parseFloat(aVal)) && !isNaN(parseFloat(bVal))) {
                        return sortDirection[key] 
                            ? parseFloat(aVal) - parseFloat(bVal)
                            : parseFloat(bVal) - parseFloat(aVal);
                    }
                    
                    // 文本排序
                    return sortDirection[key]
                        ? aVal.localeCompare(bVal)
                        : bVal.localeCompare(aVal);
                });
                
                rowsArray.forEach(row => tableBody.appendChild(row));
            });
        });
    </script>
</body>
</html>
"""
        
        with open(self.output_html, 'w', encoding='utf-8') as f:
            f.write(html)
        
        print(f"✅ HTML 报表已生成: {self.output_html}")
    
    def run(self):
        """运行完整审计流程"""
        print("🔍 开始技能使用情况盘点...")
        
        # 加载数据
        self.load_trigger_stats()
        self.load_memory()
        
        # 扫描技能
        print("📂 扫描技能目录...")
        self.scan_skills()
        
        # 分析每个技能
        print("📊 分析技能使用情况...")
        for skill_name, skill_data in self.all_skills.items():
            self.analyze_skill(skill_name, skill_data)
        
        # 转换为列表并排序
        skills_list = list(self.all_skills.values())
        skills_list.sort(key=lambda x: (-x["trigger_count"], -x["memory_hits"], x["skill_name"]))
        
        # 生成报表
        self.generate_csv(skills_list)
        self.generate_html(skills_list)
        
        print("\n✨ 盘点完成!")
        print(f"   总技能数: {len(skills_list)}")


if __name__ == "__main__":
    audit = SkillUsageAudit()
    audit.run()
