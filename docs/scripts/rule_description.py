"""
This script auto-generates docs/content/all_rules.md
"""
import os
import re


final_md = (  # noqa
"""
# Per rule explanation

This is an automatically generated list of all supported rules, their docstrings, command, and virtual environment. At \
the start of each workflow run a list is printed of which rules will be run. And while the workflow is running it \
prints which rules are being started and finished. This page is here to give an explanation to the user about what \
each rule does, and for developers to find what is, and isn't yet supported.

"""
)

path = "seq2science/rules/"


def get_dirty_docstrings(string):
    splitter = re.compile(r"(rule|checkpoint) (.*):[\s\S]*?\"\"\"([\s\S]*?)\"\"\"", re.MULTILINE)
    docstrings = {}
    for match in splitter.finditer(string):
        docstrings[match.group(2)] = match.group(3)
    return docstrings


def cleanup_docstring(dirty):
    clean = {}
    for rule, docstring in dirty.items():
        firstline = docstring.split("\n")[1]

        indentation = len(firstline) - len(firstline.lstrip())
        docstring = docstring.replace(" " * indentation, "")
        docstring = docstring.replace(" " * (indentation - 4), "")
        docstring = docstring.strip("\n")
        clean[rule] = docstring

    return clean


def get_dirty_shell(string):
    splitter = re.compile(r"(rule|checkpoint) (.*):[\s\S]*?shell:[\s\S]*?\"\"\"\\?([\s\S]*?)\"\"\"", re.MULTILINE)
    shell_cmds = {}
    for substring in string.split("\n\n\n"):
        for match in splitter.finditer(substring):
            shell_cmds[match.group(2)] = match.group(3)
    return shell_cmds


def cleanup_shell(dirty):
    clean = {}
    for rule, shell in dirty.items():
        firstline = shell.split("\n")[1]

        indentation = len(firstline) - len(firstline.lstrip())
        shellstring = "\n".join([shell_line.replace(" " * indentation, "", 1) for shell_line in shell.split("\n")])
        shellstring = shellstring.strip("\n")
        clean[rule] = shellstring

    return clean


def get_conda_env(string):
    splitter = re.compile(r"(rule|checkpoint) (.*):[\s\S]*?conda:[\s\S]*?\"\\?([\s\S]*?)\"", re.MULTILINE)
    shell_cmds = {}
    for substring in string.split("\n\n\n"):
        for match in splitter.finditer(substring):
            conda_env = match.group(3).split("/")[-1]
            conda_url = f"""https://github.com/vanheeringen-lab/seq2science/blob/docs_updates/seq2science/envs/{conda_env}"""
            shell_cmds[match.group(2)] = conda_url

    return shell_cmds


all_rules_doc = {}
all_rules_shell = {}
all_rules_conda = {}
for rules_file in os.listdir(path):
    with open(path + rules_file, 'r') as file:
        text = file.read()
    shell_cmd = cleanup_shell(get_dirty_shell(text))
    all_rules_shell.update(shell_cmd)

    docstrings = cleanup_docstring(get_dirty_docstrings(text))
    all_rules_doc.update(docstrings)

    all_rules_conda.update(get_conda_env(text))

for rule in sorted(all_rules_doc.keys()):
    docstring = all_rules_doc[rule]

    final_md += f"#### {rule}\n\n"
    final_md += f"{docstring}\n\n"
    if rule in all_rules_shell:
        final_md += "```\n"
        final_md += f"{all_rules_shell[rule]}\n"
        final_md += "```\n\n"
        if rule in all_rules_conda:
            final_md += f"[{rule} environment][{rule}].\n\n"

for rule, conda_env in all_rules_conda.items():
    final_md += f"[{rule}]: {conda_env}\n"

with open("docs/content/all_rules.md", "w") as text_file:
    text_file.write(final_md)
