#!/usr/bin/env python3
from __future__ import annotations
import re, subprocess, winreg
from _windows_helpers import is_admin, require_windows, run
NAMESPACE_PATHS=[(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace'),(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'),(winreg.HKEY_LOCAL_MACHINE,r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'),(winreg.HKEY_LOCAL_MACHINE,r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace')]
SHELL_EXT_PATHS=[(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'),(winreg.HKEY_LOCAL_MACHINE,r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'),(winreg.HKEY_LOCAL_MACHINE,r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers')]
ICLOUD_CLSIDS=['{E41DB8A7-C0A6-4D52-9C57-E41C58BAF9B8}','{F0D63F01-ED5A-4E62-9C67-E43C5E4C6E3E}','{A5A5A5A5-B4B4-C3C3-D2D2-E1E1E1E1E1E1}','{4F8B8B8B-8B8B-8B8B-8B8B-8B8B8B8B8B8B}']
def enum_subkeys(root,path):
    try:
        with winreg.OpenKey(root,path,0,winreg.KEY_READ|winreg.KEY_WRITE) as key:
            out=[]; i=0
            while True:
                try: out.append(winreg.EnumKey(key,i)); i+=1
                except OSError: break
            return out
    except FileNotFoundError: return []
def get_default(root,path):
    try:
        with winreg.OpenKey(root,path) as key: return str(winreg.QueryValueEx(key,'')[0])
    except Exception: return ''
def delete_tree(root,path):
    for child in enum_subkeys(root,path): delete_tree(root,path+'\\'+child)
    try: winreg.DeleteKey(root,path)
    except FileNotFoundError: pass
def clean_matching(paths,label,pattern):
    found=False; regex=re.compile(pattern,re.I)
    for root,path in paths:
        for child in enum_subkeys(root,path):
            child_path=path+'\\'+child; value=get_default(root,child_path)
            if regex.search(value) or regex.search(child): print(f'  发现 {label}: {value or child}'); delete_tree(root,child_path); print('  已删除 ✅'); found=True
    return found
def main():
    require_windows(); print('========================================\n  清理文件资源管理器导航栏残留项\n========================================')
    if not is_admin(): print('❌ 请以管理员身份运行此脚本！'); return 1
    print('正在清理百度网盘残留...'); found=clean_matching(NAMESPACE_PATHS,'导航项',r'百度|Baidu|网盘|同步空间') or clean_matching([(winreg.HKEY_CURRENT_USER,r'Software\Classes\CLSID')],'CLSID',r'百度|Baidu|网盘')
    if not found: print('  未发现百度网盘残留项')
    print('正在清理 iCloud 残留...'); found=clean_matching(NAMESPACE_PATHS,'导航项',r'iCloud|云盘')
    for clsid in ICLOUD_CLSIDS:
        path='Software\\Classes\\CLSID\\' + clsid
        if enum_subkeys(winreg.HKEY_CURRENT_USER,path) or get_default(winreg.HKEY_CURRENT_USER,path): delete_tree(winreg.HKEY_CURRENT_USER,path); print(f'  已删除 iCloud CLSID: {clsid} ✅'); found=True
    found=clean_matching([(winreg.HKEY_CURRENT_USER,r'Software\Classes\CLSID')],'CLSID',r'iCloud|Apple|云盘') or found
    if not found: print('  未发现 iCloud 残留项')
    print('正在清理 Shell 扩展...'); found=clean_matching(SHELL_EXT_PATHS,'Shell 扩展',r'Baidu|iCloud|Apple|百度|网盘')
    if not found: print('  未发现相关 Shell 扩展')
    print('正在重启文件资源管理器...'); run(['taskkill','/IM','explorer.exe','/F'], check=False); subprocess.Popen(['explorer.exe']); print('清理完成！请检查导航栏是否已清除'); return 0
if __name__ == '__main__': raise SystemExit(main())
