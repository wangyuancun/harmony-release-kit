#!/usr/bin/env python3
"""等提示出现后再喂口令的 pty 驱动（签名脚本专用）。

为什么需要它
------------
hap-sign-tool 在 -pwdInputMode 1 下用 JDK Console.readPassword() 读取口令。
Java 的 readPassword 会丢弃「在它开始读之前就已经进入终端输入缓冲」的字符
（type-ahead）。如果用 `printf 'pwd\\npwd\\n' | script -q /dev/null ...` 一次性
灌进去，会出现两个问题：
  1. 口令在工具关闭回显之前就写进 pty，被回显到屏幕；
  2. 口令被 readPassword 当作 type-ahead 丢弃，工具读到空串。
表现就是稳定报 "keystore password was incorrect"（而不是「没读到口令」）。

本脚本的做法
------------
用 pty 启动子进程，持续读它的输出；只有当某个提示子串真正出现在输出里之后，
才把对应口令写进 pty。此时工具已经进入 readPassword、回显已关闭，口令既不会
被回显，也不会被丢弃。

口令来源与生命周期
------------------
通过 getpass 直接从 /dev/tty 读取，不回显；只存在于本进程内存，随进程退出消失。
不写文件、不写环境变量、不进 argv（argv 里只有提示子串和要执行的命令）。

用法
----
    ptysign.py <第一处提示子串> <第二处提示子串> -- <命令> [参数...]

示例
----
    ptysign.py "KeystorePwd" "KeyPwd" -- java -jar hap-sign-tool.jar sign-app ...
"""
import getpass
import os
import pty
import select
import subprocess
import sys


def main():
    try:
        sep = sys.argv.index("--")
    except ValueError:
        print(__doc__, file=sys.stderr)
        return 2
    prompts = sys.argv[1:sep]
    cmd = sys.argv[sep + 1:]
    if len(prompts) != 2 or not cmd:
        print(__doc__, file=sys.stderr)
        return 2

    if not sys.stdin.isatty() and not os.environ.get("PTYSIGN_NO_TTY"):
        print("请在真实终端里运行（需要交互输入口令）。", file=sys.stderr)
        return 2

    pwd = getpass.getpass("密钥库口令（不回显）: ")
    if not pwd:
        print("口令为空，退出。", file=sys.stderr)
        return 1
    key_pwd = getpass.getpass("密钥口令（与密钥库口令相同则直接回车）: ") or pwd

    master, slave = pty.openpty()
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave,
                            close_fds=True, preexec_fn=os.setsid)
    os.close(slave)

    answers = [(prompts[0], pwd), (prompts[1], key_pwd)]
    buf = b""
    idx = 0
    while True:
        r, _, _ = select.select([master], [], [], 0.2)
        if r:
            try:
                data = os.read(master, 4096)
            except OSError:
                break
            if not data:
                break
            sys.stdout.buffer.write(data)
            sys.stdout.flush()
            buf += data
            # 关键：只在提示真正打印出来之后才写入口令
            while idx < len(answers) and answers[idx][0].encode() in buf:
                os.write(master, (answers[idx][1] + "\n").encode())
                idx += 1
                buf = b""
        elif proc.poll() is not None:
            break
    os.close(master)
    return proc.wait()


if __name__ == "__main__":
    sys.exit(main())
