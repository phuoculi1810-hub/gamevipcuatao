# 📁 FILES NÊN PUSH LÊN GITHUB

## ✅ FILES BẮT BUỘC PHẢI PUSH

### Core Files
- ✅ `.gitignore` - Quan trọng để ignore files không cần thiết
- ✅ `server.js` - Railway server chính
- ✅ `package.json` - Dependencies cho Node.js
- ✅ `README.md` - Documentation chính
- ✅ `DEPLOYMENT.md` - Hướng dẫn deployment
- ✅ `GIT_GUIDE.md` - Hướng dẫn Git

### Lua Scripts
- ✅ `scripts/main.lua` - Main automation script
- ✅ `scripts/pullup_check.lua` - Pullup monitor với timeout
- ✅ `scripts/raid1.lua` - Raid 1 automation
- ✅ `scripts/raid2.lua` - Raid 2 automation

### Utility Scripts
- ✅ `utils/disable_lockon.lua` - Tắt lock-on mobile
- ✅ `utils/buy_vest.lua` - Auto mua vest
- ✅ `utils/click_pullup.lua` - Click máy pullup

### Game Scripts
- ✅ `Loader.lua` - Game loader script

### Documentation
- ✅ `logic.txt` - Logic documentation

## ❌ FILES KHÔNG ĐƯỢC PUSH (Đã có trong .gitignore)

- ❌ `node_modules/` - Dependencies (sẽ được cài bởi `npm install`)
- ❌ `package-lock.json` - Lock file (optional)
- ❌ `.env` - Environment variables (nếu có)
- ❌ `.env.local` - Local environment variables
- ❌ `railway.toml` - Railway config (nếu có sensitive info)
- ❌ `.railway/` - Railway cache
- ❌ `logs/` - Log files
- ❌ `*.log` - Log files
- ❌ `.DS_Store` - macOS file
- ❌ `Thumbs.db` - Windows file

---

## 🚀 LỆNH GIT ĐỂ PUSH

### Cách 1: Push tất cả (trừ files trong .gitignore)
```bash
git init
git add .
git commit -m "Initial commit - OKUPDATERAID System"
git branch -M main
git remote add origin https://github.com/USERNAME/okupdateraid.git
git push -u origin main
```

### Cách 2: Push chỉ files cần thiết
```bash
git init
git add .gitignore
git add server.js
git add package.json
git add README.md
git add DEPLOYMENT.md
git add scripts/
git add utils/
git add raid1/
git add raid2/
git add Loader.lua
git add logic.txt
git add *.lua  # Thêm các file .lua còn lại
git add *.txt  # Thêm các file .txt reference
git commit -m "Initial commit - OKUPDATERAID System"
git branch -M main
git remote add origin https://github.com/USERNAME/okupdateraid.git
git push -u origin main
```

---

## 📊 CẤU TRÚC RECOMMENDED

```
okupdateraid/
├── .gitignore              ✅ Push
├── server.js               ✅ Push
├── package.json            ✅ Push
├── README.md               ✅ Push
├── DEPLOYMENT.md           ✅ Push
├── GIT_GUIDE.md            ✅ Push (file này)
├── scripts/                ✅ Push (toàn bộ folder)
│   ├── main.lua
│   ├── pullup_check.lua
│   ├── raid1.lua
│   └── raid2.lua
├── utils/                  ✅ Push (toàn bộ folder)
│   ├── disable_lockon.lua
│   ├── buy_vest.lua
│   └── click_pullup.lua
├── Loader.lua              ✅ Push
└── logic.txt               ✅ Push
```

---

## 💡 KHUYẾN NGHỊ

1. **Push tất cả trừ node_modules:** .gitignore đã cấu hình sẵn, chỉ cần `git add .`
2. **Private Repository:** Nên để repo ở chế độ Private vì đây là script game
3. **Backup:** Push cả các file reference để backup
4. **Documentation:** Luôn giữ README và DEPLOYMENT.md cập nhật
