#!/usr/bin/env python3
import json
import re
from pathlib import Path
from datetime import datetime


def slugify(text):
    """Convert text to URL-friendly slug."""
    text = text.lower().strip()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[-\s]+', '-', text)
    return text[:50]


def format_date(date_str):
    """Format ISO date to readable format."""
    if not date_str:
        return ''
    try:
        dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d %H:%M')
    except Exception:
        return date_str


def json_to_markdown(data):
    """Convert issue JSON to Markdown format."""
    title = data.get('title', 'Untitled')
    number = data.get('number', '?')
    url = data.get('html_url') or data.get('url', '')
    state = data.get('state', 'unknown')
    updated_at = data.get('updated_at', '')
    body = (data.get('body') or '').strip()
    # github-backup stores comments in 'comment_data' field
    comments = data.get('comment_data') or []

    md = f"# [{number} - {title}]({url})\n\n"
    md += f"**Status:** {state}  \n"
    md += f"**Updated:** {format_date(updated_at)}\n\n"

    if body:
        md += "## Описание\n\n"
        md += f"{body}\n\n"

    if comments:
        md += "---\n\n"
        md += "## Комментарии\n\n"
        for i, comment in enumerate(comments, 1):
            comment_body = (comment.get('body') or '').strip()
            created_at = comment.get('created_at', '')
            html_url = comment.get('html_url', '')
            author = comment.get('user', {}).get('login', 'unknown')

            if html_url:
                md += f"### [@{author} — {format_date(created_at)}]({html_url})\n\n"
            else:
                md += f"### @{author} — {format_date(created_at)}\n\n"
            md += f"{comment_body}\n\n"

    return md, len(comments)


def has_maincard_label(data):
    """Check if issue has MainCard label."""
    labels = data.get('labels', [])
    if not isinstance(labels, list):
        return False
    for label in labels:
        name = label.get('name') if isinstance(label, dict) else label
        if name and name.lower() == 'maincard':
            return True
    return False


def is_valid_issue(data):
    """Check if JSON data represents a valid issue."""
    return isinstance(data, dict) and 'title' in data and 'number' in data


def convert_issues_to_markdown(issues_dir):
    """Convert issue JSON files to Markdown."""
    issues_path = Path(issues_dir)

    if not issues_path.exists():
        print(f"Directory {issues_dir} does not exist")
        return

    json_files = list(issues_path.glob("*.json"))
    total_issues = 0
    total_comments = 0

    for json_file in json_files:
        try:
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)

            if not is_valid_issue(data):
                json_file.unlink()
                continue

            issue_number = data['number']
            issue_title = data.get('title', 'untitled')

            # Determine target path
            if has_maincard_label(data):
                target_path = issues_path / 'MainCard'
                target_path.mkdir(exist_ok=True)
            else:
                target_path = issues_path

            # Create markdown file
            slug = slugify(issue_title)
            md_name = f"{issue_number}-{slug}.md"
            md_path = target_path / md_name

            markdown_content, comment_count = json_to_markdown(data)

            with open(md_path, 'w', encoding='utf-8') as f:
                f.write(markdown_content)

            print(f"Converted: {json_file.name} -> {md_path.relative_to(issues_path)} ({comment_count} comments)")

            json_file.unlink()
            total_issues += 1
            total_comments += comment_count

        except Exception as e:
            print(f"Error processing {json_file}: {e}")

    print(f"\nProcessed {total_issues} issues, {total_comments} comments")


if __name__ == "__main__":
    convert_issues_to_markdown("issues")
