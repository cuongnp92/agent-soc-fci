# Ansible Deploy - Velociraptor Agent

Playbook Ansible để deploy Agent Velociraptor lên các node Linux (Debian-based)
phục vụ thu thập log về SIEM. Hỗ trợ đăng nhập root bằng **password**, **SSH key**,
hoặc **kết hợp cả hai** (mỗi VM một kiểu khác nhau) — cấu hình tại `inventory.ini`.

## Cấu trúc thư mục

Theo đúng thực tế trên GitHub (`agent-soc-fci/agents-velociraptor/ansible_deploy/`):

```
ansible_deploy/
├── old/                      # (*) Backup/file cũ - xem ghi chú bên dưới
├── scripts/
│   └── agent-velociraptor.sh   # Script cài đặt agent (tải .deb từ GitHub, dpkg -i, start service)
├── ansible.cfg                # Config chung: inventory mặc định, tắt host key checking
├── install_agent.yml          # Playbook chính: kiểm tra, cài đặt, verify agent
├── inventory.ini              # Danh sách node (IP + thông tin đăng nhập: password và/hoặc SSH key)
├── test_run.yml               # Playbook debug tối giản (dùng khi cần chẩn đoán lỗi)
```

## Yêu cầu môi trường (trên máy chạy Ansible - controller)

```bash
# Cài pip (nếu chưa có)
sudo apt update
sudo apt install python3-pip -y

# Cài Ansible qua pip (bản mới nhất, khuyên dùng thay vì apt/PPA)
python3 -m pip install --user ansible

# Thêm vào PATH nếu chưa có
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Cài sshpass (chỉ cần nếu có ÍT NHẤT 1 node dùng password để login)
sudo apt install sshpass -y
```

Kiểm tra:
```bash
which ansible
ansible --version
```

> Nâng cấp Ansible sau này chỉ cần chạy lại: `python3 -m pip install --upgrade --user ansible`

## Cấu hình `inventory.ini`

`inventory.ini` hỗ trợ 3 kiểu, chọn 1 kiểu phù hợp thực tế hạ tầng của bạn:

### Kiểu 1 — Toàn bộ node dùng password

```ini
[vms]
vm01 ansible_host=10.100.120.82
vm02 ansible_host=10.100.120.122

[vms:vars]
ansible_user=root
ansible_ssh_pass="MatKhauThat123!"
ansible_connection=ssh
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
```
> Nếu mỗi VM có password khác nhau, khai báo `ansible_ssh_pass` riêng ngay trên từng dòng host thay vì để chung ở `[vms:vars]`.

### Kiểu 2 — Toàn bộ node dùng SSH key

```ini
[vms]
vm01 ansible_host=10.100.120.82
vm02 ansible_host=10.100.120.122

[vms:vars]
ansible_user=root
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_connection=ssh
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
```
> Điều kiện: public key (`~/.ssh/id_ed25519.pub`) phải đã được thêm vào `~/.ssh/authorized_keys` của root trên từng VM trước (dùng `ssh-copy-id` hoặc module `authorized_key` để đẩy hàng loạt).

### Kiểu 3 — Kết hợp (một số node có key, số còn lại chưa có → fallback sang password)

```ini
[vms:vars]
ansible_user=root
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_pass="MatKhauMacDinhNeuChuaCoKey"
ansible_connection=ssh
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=publickey,password'
```
SSH sẽ tự thử `publickey` trước; node nào chưa có key sẽ tự động fallback sang `password`. Cần cài `sshpass` cho kiểu này. Dùng khi đang trong giai đoạn **chuyển dần** từ password sang key cho 38 VM — sau khi toàn bộ node đã có key (`ansible vms -m ping` ra `pong` hết), nên dọn `ansible_ssh_pass` khỏi file, chuyển hẳn về Kiểu 2 cho an toàn và gọn hơn.

## Cấu hình khác trước khi chạy

1. Trong `install_agent.yml`, kiểm tra lại biến `service_name` (mặc định `velociraptor_client`) khớp đúng tên service agent thật đang dùng.
2. Trong `scripts/agent-velociraptor.sh`, kiểm tra `DEB_URL` trỏ đúng file `.deb` trên GitHub, và 2 endpoint SIEM (`PRIVATE_HOST`/`PUBLIC_HOST`) đúng với hạ tầng thật.
3. `ansible.cfg` không cần chỉnh gì thêm dù dùng password hay key — file này chỉ cấu hình hành vi chung (đường dẫn inventory, timeout, pipelining), tách biệt hoàn toàn khỏi cách xác thực từng host.

## Cách chạy playbook

### 1. Chạy thử trên 1-2 node trước khi apply toàn bộ

```bash
cd ansible_deploy
ansible-playbook install_agent.yml --limit vm01,vm02
```

### 2. Chạy toàn bộ (mặc định cuốn chiếu 10 node/lần nhờ `serial: 10`)

```bash
ansible-playbook install_agent.yml
```

### 3. Tăng tốc độ song song (số fork chạy đồng thời)

```bash
ansible-playbook install_agent.yml -f 20
```

### 4. Debug chi tiết khi có lỗi (xem đầy đủ output/stdout/stderr từng task)

```bash
ansible-playbook install_agent.yml --limit vm04 -v
```

### 5. Kiểm tra kết nối SSH tới toàn bộ node trước khi deploy

```bash
ansible vms -m ping
```

### 6. Playbook debug tối giản (khi nghi ngờ lỗi nằm ở tầng Ansible, không phải logic playbook chính)

```bash
ansible-playbook test_run.yml --limit <tên_node>
```
Playbook này bỏ hết logic `already_installed`/marker, chỉ upload + chạy script + in toàn bộ kết quả thô (`register`) ra màn hình — dùng để cô lập vấn đề khi playbook chính báo lỗi khó hiểu.

## Cơ chế hoạt động của `install_agent.yml`

1. **Ping** kiểm tra kết nối SSH tới từng node.
2. **Kiểm tra đã cài chưa**: check service `velociraptor_client` có đang `active` không (qua `systemd`). Nếu đã active → **SKIP** toàn bộ bước cài đặt cho node đó (tránh cài lại/mất thời gian).
3. Nếu **chưa cài**:
   - Upload `scripts/agent-velociraptor.sh` lên `/home/agent-velociraptor.sh` (cấp quyền `0755` luôn khi copy).
   - Chạy script (script tự tải `.deb` từ GitHub, `dpkg -i`, start service, verify).
   - Tạo marker file `/home/.agent_installed` nếu cài thành công (chỉ mang tính audit, không dùng để quyết định skip).
4. **Kiểm tra kết quả cuối cùng** (luôn chạy dù skip hay cài mới): xác nhận service có `active` không, có process đang chạy không.
5. **Play cuối** in báo cáo tổng hợp `THÀNH CÔNG` / `THẤT BẠI` cho từng node.

## Xử lý sự cố thường gặp

| Lỗi | Nguyên nhân | Cách fix |
|---|---|---|
| `unreachable=1` trong PLAY RECAP | Sai password / VM tắt / firewall chặn port 22 | `ansible <node> -m ping -vvv` để xem lỗi chi tiết |
| `ModuleNotFoundError: ansible.module_utils.six.moves` | Xung đột Python/gói ansible trên target, hoặc Ansible controller quá cũ | Kiểm tra `ansible --version` trên controller; nâng cấp qua `pip install --upgrade --user ansible` |
| `no command given` / `Unsupported parameters for (command) module` | Phiên bản Ansible không tương thích với `cmd:` param hoặc FQCN (`ansible.builtin.x`) kết hợp free-form | Playbook đã dùng tên module ngắn (`shell`, `command`...) thay vì FQCN để tránh lỗi này |
| Service đã cài nhưng bị skip nhầm dù không chạy | Marker file cũ còn sót | Logic hiện tại chỉ tin vào trạng thái `systemd` thật, không dùng marker để quyết định skip |

| Sai `PreferredAuthentications` khi dùng Kiểu 3 (mix) khiến SSH không tự fallback | Thiếu cờ `-o PreferredAuthentications=publickey,password` trong `ansible_ssh_common_args`, hoặc thiếu `sshpass` | Thêm đúng cờ như hướng dẫn Kiểu 3; `sudo apt install sshpass -y` |
| `Permission denied (publickey)` dù đã cấu hình key | Public key chưa được thêm vào `~/.ssh/authorized_keys` của root trên VM đó, hoặc sai đường dẫn `ansible_ssh_private_key_file` | Kiểm tra `cat ~/.ssh/authorized_keys` trên VM đích; xác nhận đúng path private key trong inventory |

## Bảo mật

- Nếu dùng **password** (Kiểu 1 hoặc Kiểu 3): `inventory.ini` chứa password root dạng plaintext — **không commit** file chứa password thật lên Git công khai. Cân nhắc dùng Ansible Vault để mã hoá nếu repo có nhiều người truy cập.
- Nếu dùng **SSH key** (Kiểu 2): an toàn hơn hẳn, không lo lộ credential qua file — chỉ cần đảm bảo private key trên máy controller có quyền `chmod 600` và không bị chia sẻ.
- Về lâu dài, khuyến nghị chuyển hẳn sang Kiểu 2 (SSH key thuần) cho toàn bộ 38 VM, loại bỏ hoàn toàn password khỏi luồng vận hành.
- Repo GitHub chứa file `.deb` nếu là private, cần set `GITHUB_TOKEN` khi script tải file (xem biến `GITHUB_TOKEN` trong `agent-velociraptor.sh`).
