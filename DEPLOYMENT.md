# 🚀 HƯỚNG DẪN DEPLOYMENT - GITHUB & RAILWAY

## 📋 BƯỚC 1: CHUẨN BỊ GITHUB

### 1.1 Tạo Repository trên GitHub

1. Đăng nhập vào [GitHub](https://github.com)
2. Click vào **+** → **New repository**
3. Điền thông tin:
   - **Repository name**: `okupdateraid` (hoặc tên bạn muốn)
   - **Description**: `Auto Raid System with Railway Control`
   - **Public/Private**: Chọn **Private** (khuyên dùng cho script game)
4. Click **Create repository**

### 1.2 Push Code lên GitHub

Mở terminal/command prompt tại thư mục project:

```bash
# Khởi tạo git
git init

# Thêm tất cả file
git add .

# Commit lần đầu
git commit -m "Initial commit - OKUPDATERAID System"

# Đổi tên branch thành main (nếu cần)
git branch -M main

# Thêm remote repository
git remote add origin https://github.com/USERNAME/okupdateraid.git

# Push lên GitHub
git push -u origin main
```

**Lưu ý:** Thay `USERNAME` bằng username GitHub của bạn.

Nếu gặp lỗi authentication:
```bash
# Sử dụng GitHub CLI (nếu đã cài)
gh auth login

# Hoặc sử dụng personal access token
# Settings → Developer settings → Personal access tokens → Generate new token
```

---

## 🚂 BƯỚC 2: DEPLOY LÊN RAILWAY

### 2.1 Cài Railway CLI

**Windows:**
```bash
# Sử dụng npm
npm install -g @railway/cli

# Hoặc tải trực tiếp từ https://railway.app/download
```

**Kiểm tra cài đặt:**
```bash
railway --version
```

### 2.2 Đăng nhập Railway

```bash
railway login
```

- Railway sẽ mở trình duyệt
- Đăng nhập tài khoản Railway của bạn
- Quay lại terminal sau khi đăng nhập xong

### 2.3 Tạo Project Railway

```bash
# Tạo project mới
railway init

# Railway sẽ hỏi:
# - What is the name of your project? → okupdateraid
# - Select the region → Singapore (hoặc region gần bạn nhất)
```

### 2.4 Cấu hình Project

**Tạo file `railway.toml` trong thư mục project:**

```toml
[build]
builder = "NIXPACKS"

[deploy]
healthcheckPath = "/health"
healthcheckTimeout = 300
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 10
```

### 2.5 Thêm Database (Tùy chọn - Không bắt buộc)

Nếu muốn lưu state lâu dài:

```bash
# Thêm PostgreSQL database
railway add postgresql

# Railway sẽ cung cấp DATABASE_URL trong environment variables
```

### 2.6 Deploy lên Railway

```bash
# Deploy lần đầu
railway up

# Railway sẽ:
# 1. Upload code
# 2. Cài đặt dependencies (npm install)
# 3. Build project
# 4. Start server
```

### 2.7 Lấy Railway URL

Sau khi deploy thành công:

```bash
# Lấy URL của project
railway domain

# Hoặc xem trên dashboard
railway open
```

URL sẽ có dạng: `https://okupdateraid-production.up.railway.app`

---

## 🔧 BƯỚC 3: CẤU HÌNH LUA SCRIPTS

### 3.1 Cập nhật Railway URL

Mở các file sau và cập nhật `RAILWAY_URL`:

**File: `scripts/main.lua`**
```lua
-- Railway Config
local RAILWAY_URL = "https://okupdateraid-production.up.railway.app" -- Thay bằng URL của bạn
local ACCOUNT_ID = player.Name
```

**File: `scripts/raid1.lua`**
```lua
-- Railway Config
local RAILWAY_URL = "https://okupdateraid-production.up.railway.app" -- Thay bằng URL của bạn
local ACCOUNT_ID = LocalPlayer.Name
```

**File: `scripts/raid2.lua`**
```lua
-- Railway Config
local RAILWAY_URL = "https://okupdateraid-production.up.railway.app" -- Thay bằng URL của bạn
local ACCOUNT_ID = LocalPlayer.Name
```

### 3.2 Test Railway Connection

Trước khi chạy script chính, test kết nối:

```lua
-- Test script (chạy trong Roblox Studio)
local HttpService = game:GetService("HttpService")

local success, response = pcall(function()
    return HttpService:RequestAsync({
        Url = "https://okupdateraid-production.up.railway.app/health",
        Method = "GET"
    })
end)

if success then
    print("✅ Railway connection OK!")
    print(response.Body)
else
    print("❌ Railway connection failed:", response)
end
```

---

## 🔄 BƯỚC 4: UPDATE CODE SAU KHI DEPLOY

### 4.1 Update Code Local

```bash
# Thay đổi code
# ...

# Commit thay đổi
git add .
git commit -m "Update feature XYZ"
git push
```

### 4.2 Deploy Lên Railway

```bash
# Railway sẽ tự động deploy khi có code mới
railway up

# Hoặc enable auto-deploy
railway variables set RAILWAY_GIT_COMMIT_DEPLOY_ENABLED=true
```

### 4.3 Monitor Logs

```bash
# Xem logs real-time
railway logs

# Xem logs của service cụ thể
railway logs --service api
```

---

## 🎮 BƯỚC 5: CHẠY SCRIPT TRONG GAME

### 5.1 Chạy Main Script

1. Mở Roblox Studio hoặc join game
2. Execute `Loader.lua`
3. Script sẽ tự động:
   - Connect đến Railway server
   - Bắt đầu quy trình automation
   - Send status updates về Railway

### 5.2 Monitor qua Railway Dashboard

1. Mở Railway URL: `https://okupdateraid-production.up.railway.app`
2. Xem dashboard với các tính năng:
   - Account status real-time
   - Cooldown timers
   - Combat/Pullup status
   - Control buttons (Fire Raid, Hop Server, Stop Script)

---

## 🛠️ TROUBLESHOOTING

### Lỗi: Railway connection failed

**Nguyên nhân:** HTTP requests bị block bởi Roblox

**Giải pháp:**
- Đảm bảo Railway URL đúng
- Test với `/health` endpoint trước
- Kiểm tra console logs trong Roblox Studio

### Lỗi: Cannot push to GitHub

**Nguyên nhân:** Authentication error

**Giải pháp:**
```bash
# Sử dụng GitHub CLI
gh auth login

# Hoặc setup SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"
# Thêm key vào GitHub Settings → SSH and GPG keys
```

### Lỗi: Railway deploy failed

**Nguyên nhân:** Build error hoặc missing dependencies

**Giải pháp:**
```bash
# Kiểm tra logs
railway logs

# Xóa cache và rebuild
railway destroy
railway init
railway up
```

### Lỗi: Port already in use

**Nguyên nhân:** Port 3000 đang được sử dụng

**Giải pháp:**
```bash
# Windows
netstat -ano | findstr :3000
taskkill /PID <PID> /F

# Hoặc đổi port trong server.js
const PORT = process.env.PORT || 3001;
```

---

## 📊 MONITORING & DEBUGGING

### Xem Logs Railway

```bash
# Real-time logs
railway logs

# Logs 100 dòng gần nhất
railway logs -n 100

# Logs theo service
railway logs --service api
```

### Xem Metrics

```bash
# Mở dashboard
railway open

# Xem metrics (CPU, Memory, Network)
railway metrics
```

### Environment Variables

```bash
# List tất cả variables
railway variables

# Thêm variable mới
railway variables set RAILWAY_URL=https://...

# Xóa variable
railway variables remove RAILWAY_URL
```

---

## 🔐 SECURITY BEST PRACTICES

1. **Private Repository:** Giữ repo GitHub ở chế độ Private
2. **Environment Variables:** Không commit sensitive data
3. **API Keys:** Sử dụng Railway environment variables cho keys
4. **Rate Limiting:** Thêm rate limiting trong server.js nếu cần
5. **Authentication:** Thêm authentication cho Railway API (nếu deploy public)

---

## 📞 SUPPORT

- **Railway Documentation:** https://docs.railway.app
- **Railway Discord:** https://discord.gg/railway
- **GitHub Docs:** https://docs.github.com

---

## ✅ CHECKLIST TRƯỚC KHI DEPLOY

- [ ] Đã push code lên GitHub
- [ ] Đã cài Railway CLI
- [ ] Đã login vào Railway
- [ ] Đã tạo Railway project
- [ ] Đã cấu hình railway.toml
- [ ] Đã test Railway connection
- [ ] Đã cập nhật RAILWAY_URL trong Lua scripts
- [ ] Đã test script trong Roblox Studio
- [ ] Đã monitor Railway dashboard
