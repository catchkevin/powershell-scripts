# 🚀 File Copy / Move Utility

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)
![Version](https://img.shields.io/badge/Version-2.0-green)

---

## 📌 Overview

A **high-performance PowerShell file transfer utility** designed for:

- Speed testing
- Bulk file operations
- Operational tooling
- Performance benchmarking

This script goes far beyond standard copy tools by adding **real-time visibility, structured logging, and flexible control**.

---

## ⚡ Key Features

- ✅ Copy **AND** Move support
- ✅ Individual, Multiple, and All file modes
- ✅ Wildcard file selection (`*.csv`, `file_*`)
- ✅ Parallel processing (1–64 threads)
- ✅ Real-time performance metrics (MB/s, ETA)
- ✅ Structured logging (TXT, CSV, JSON)
- ✅ UTC-based daily log rotation
- ✅ Overwrite control with `[A]ll`
- ✅ Clean console output (mode-aware)

---

## 🚀 Quick Start

1. Run script
2. Select:
   - Copy or Move
   - File Mode
3. Select files
4. Confirm (if multiple)
5. Choose overwrite behavior
6. Choose Serial or Parallel
7. Monitor progress

---

## 🖥 Example Output

```
2026-03-28 09:30:01 |  45% | 450/1000 MB | 120 MB/s | ETA 00:00:05 | CopyId abc-123 | ParallelCount 8
```

---

## 📊 Logging

Supports:

- TXT → readable logs
- CSV → structured analytics
- JSON → machine-readable (NDJSON)

### Log Fields

- Timestamp
- CopyId (GUID)
- Status
- FileName
- FileSize (Bytes → TB)
- Throughput
- ETA
- Duration
- ErrorMessage

---

## ⚙️ Performance Tips

| Scenario | Recommendation |
|--------|--------------|
| Local SSD → SSD | 8–16 threads |
| Network transfer | 4–8 threads |
| Large files | Serial or low threads |
| Many small files | Higher threads |

---

## ⚠️ Troubleshooting

### Parallel mode not working
- Ensure PowerShell 7 OR ThreadJob module installed

### Slow performance
- Check disk I/O bottleneck
- Reduce thread count

### Logging not creating files
- Verify permissions
- Confirm UTC date rollover

---

## 🧠 Design Philosophy

- **Control** → Safe prompts + confirmations
- **Visibility** → Real-time + logs
- **Performance** → Parallel support
- **Clean UX** → Context-aware output

---

## 📌 Summary

This utility is built for **real-world operations**, not just scripting convenience.

It delivers:

- Speed
- Visibility
- Safety
- Flexibility

