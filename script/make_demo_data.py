#!/usr/bin/env python3
"""Create fictional Polaris data in an empty directory, never copy user data."""

import argparse
import calendar
import json
from datetime import datetime, time, timedelta, timezone
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5


def identifier(name):
    return str(uuid5(NAMESPACE_URL, "https://github.com/stardime-bingo/Polaris/demo/" + name)).upper()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Empty destination for fictional JSON files")
    output = parser.parse_args().directory.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("Destination must be empty. Existing data will not be overwritten.")

    now = datetime.now().astimezone()
    epoch = datetime(2001, 1, 1, tzinfo=timezone.utc)
    stamp = lambda date: (date - epoch).total_seconds()
    at_nine = lambda day: datetime.combine(day, time(9), tzinfo=now.tzinfo)
    week_end = at_nine(now.date() + timedelta(days=6 - now.weekday()))
    month_end = at_nine(now.date().replace(day=calendar.monthrange(now.year, now.month)[1]))
    list_id = identifier("list")
    labels = [
        {"id": identifier("reading"), "name": "阅读", "colorHex": "7850ED", "icon": "book", "listId": list_id},
        {"id": identifier("life"), "name": "生活", "colorHex": "FF805F", "icon": "leaf", "listId": list_id},
    ]

    def goal(key, title, period, due, priority, quadrant, position, steps=(), pinned=False, label=None):
        return {
            "id": identifier(key), "title": title, "notes": "用于演示的虚构目标，可自由修改。",
            "createdAt": stamp(now - timedelta(days=3)), "priorityRaw": priority,
            "dueDate": stamp(due), "reminderOffsetRaw": 0, "sortOrder": position,
            "listId": list_id, "labelIds": [identifier(label)] if label else [],
            "isPinned": pinned, "goalPeriod": period, "hasDueTime": False, "quadrant": quadrant,
            "steps": [{"id": identifier(key + "/" + str(i)), "title": title, "isCompleted": done}
                      for i, (title, done) in enumerate(steps)],
        }

    tasks = [
        goal("portfolio", "上线个人作品集", "month", month_end, 2, 0, 0,
             [("选好三个作品", True), ("完善项目介绍", False), ("发布并分享", False)], pinned=True),
        goal("reading-goal", "完成本周阅读", "week", week_end, 1, 1, 1, label="reading"),
        goal("organize", "整理桌面和下载文件", "week", week_end, 0, 3, 2),
        goal("cooking", "学会一道新料理", "month", month_end, 1, 1, 3,
             [("选一份食谱", True), ("周末试做", False)], label="life"),
        goal("walk", "周末去公园散步", "week", week_end, 0, 2, 4, label="life"),
    ]
    tasks[-1]["completedAt"] = stamp(now - timedelta(days=1))
    files = {
        "tasks.json": tasks,
        "lists.json": [{"id": list_id, "name": "我的目标", "createdAt": stamp(now),
                        "isDefault": True, "colorHex": "C6FF4A"}],
        "labels.json": labels,
    }
    for filename, content in files.items():
        (output / filename).write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Fictional demo data created: {output}")


if __name__ == "__main__":
    main()
