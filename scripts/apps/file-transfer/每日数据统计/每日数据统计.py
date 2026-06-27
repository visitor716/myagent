import os
import re
from datetime import datetime, timedelta

# ------------------- 配置 -------------------

# 数据文件的根目录（网络共享盘路径）
# 原来是固定的日期目录（例如 0822），改为动态根据当前时间拼接“昨天”的目录，格式为：YYYY年M月D
base_dir_root = r"\\10.116.33.161\dr共享盘\每日产能卡堵数据统计"
# 计算昨天的日期并格式化为示例中的形式（例如 2025年8月31）
yesterday = datetime.now() - timedelta(days=1)
date_segment = f"{yesterday.year}年{yesterday.month}月{yesterday.day}"
# 最终的 base_dir 为根目录加上昨天的日期段
base_dir = os.path.join(base_dir_root, date_segment)
# 需要统计的机台名称列表
machines = ["4144A", "4144B", "4070A", "4070B"]

# 进料报警编号列表
infeed_ids = ["NO.21", "NO.22", "NO.23","NO.24","NO.47" "NO.70", "NO.107", ]
# 出料报警编号列表
outfeed_ids = ["NO.33","NO.149", "NO.40", "NO.108", "NO.43"]

# 统计的时间范围（字符串格式）
start_time = "08:00:00"
end_time = "20:00:00"

# ------------------- 函数 -------------------
def parse_time(time_str):
    """将 HH:MM:SS 格式的时间字符串转成秒数，便于后续计算时间间隔"""
    h, m, s = map(int, time_str.split(":"))
    return h*3600 + m*60 + s

def main():
    # ------------------- 主程序 -------------------
    for machine in machines:
        print(f"\n正在处理机台 {machine}...")
        # 拼接出当前机台的数据文件夹路径
        machine_dir = os.path.join(base_dir, machine)

        # 各类数据文件的路径
        card_file = os.path.join(machine_dir, "卡堵数据.txt")
        offset_file = os.path.join(machine_dir, "放偏数据.txt")
        idle_file = os.path.join(machine_dir, "待机时间.txt")

        # 初始化统计变量
        infeed_count = 0      # 进料报警次数
        outfeed_count = 0     # 出料报警次数
        ano16_count = 0       # ANO16放偏次数
        total_capacity = None # 总产能
        idle_hours = None     # 待机小时数

        # ------------------- 卡堵次数统计 -------------------
        last_infeed_time = {}   # 记录每个进料报警编号上次报警的时间（秒）
        last_outfeed_time = {}  # 记录每个出料报警编号上次报警的时间（秒）
        if os.path.exists(card_file):
            with open(card_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    # 提取每行的时间戳（格式为HH:MM:SS）
                    time_match = re.match(r"(\d{2}:\d{2}:\d{2})", line)
                    if not time_match:
                        continue
                    time_str = time_match.group(1)
                    # 判断时间是否在统计范围内
                    if time_str < start_time or time_str > end_time:
                        continue
                    time_sec = parse_time(time_str)

                    # 检查进料报警编号
                    for code in infeed_ids:
                        if code in line:
                            last_time = last_infeed_time.get(code, -999)
                            # 距离上次报警超过10秒才计数，避免重复
                            if time_sec - last_time > 10:
                                infeed_count += 1
                                last_infeed_time[code] = time_sec

                    # 检查出料报警编号
                    for code in outfeed_ids:
                        if code in line:
                            last_time = last_outfeed_time.get(code, -999)
                            # 距离上次报警超过10秒才计数
                            if time_sec - last_time > 10:
                                outfeed_count += 1
                                last_outfeed_time[code] = time_sec

        # ------------------- 放偏次数统计 -------------------
        if os.path.exists(offset_file):
            with open(offset_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    # 提取时间戳
                    time_match = re.match(r"(\d{2}:\d{2}:\d{2})", line)
                    if not time_match:
                        continue
                    time_str = time_match.group(1)
                    # 判断时间是否在统计范围内
                    if time_str < start_time or time_str > end_time:
                        continue
                    # 检查是否为ANO16放偏报警
                    if "ANO16" in line:
                        ano16_count += 1

        # ------------------- 待机时间与产能统计 -------------------
        if os.path.exists(idle_file):
            with open(idle_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    # 只统计20:00:00时刻的数据
                    if line.startswith("20:00:00"):
                        # 提取总产能
                        cap_match = re.search(r"当日总产能:\s*(\d+)", line)
                        # 提取待机时间（秒）
                        idle_match = re.search(r"待机时间:\s*(\d+)", line)
                        if cap_match:
                            total_capacity = int(cap_match.group(1))
                        if idle_match:
                            idle_sec = int(idle_match.group(1))
                            idle_hours = round(idle_sec / 3600, 2)  # 转换为小时并保留两位小数

        # ------------------- 输出统计结果 -------------------
        # 结果保存到机台目录下的统计结果文件
        output_file = os.path.join(machine_dir, f"{machine_dir}_统计结果.txt")
        
        # 确保目录存在再写文件
        os.makedirs(machine_dir, exist_ok=True)
        with open(output_file, "w", encoding="utf-8") as out:
            out.write(f"{machine} 统计结果：\n")
            out.write(f"进料报警次数 (08-20点，间隔>10s): {infeed_count}\n")
            out.write(f"出料报警次数 (08-20点，间隔>10s): {outfeed_count}\n")
            out.write(f"ANO16放偏次数 (08-20点): {ano16_count}\n")
            out.write(f"当日总产能 (20:00:00): {total_capacity if total_capacity is not None else '无数据'}\n")
            out.write(f"待机时间(h,20:00:00): {idle_hours if idle_hours is not None else '无数据'}\n")

        # 打印提示，告知用户统计已完成
        print(f"{machine} 统计完成，结果已保存到 {output_file}")


if __name__ == '__main__':
    main()