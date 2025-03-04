# **sync.sh - Hypothetical Input & Output Example**

## **Purpose**
The `sync.sh` script facilitates the synchronization of a folder between a source VM and a destination VM. The synchronization can either occur directly if there is a direct SSH connection or indirectly through an intermediary VM if direct access is not available. This script uses `rsync` to handle the file transfer and logs each operation.

## **Workflow Overview**

1. **Input**: The script prompts the user for SSH connection details (source VM, destination VM, and folder path to synchronize).
2. **Sync Process**: The script checks SSH connectivity between the VMs, and performs either a direct or indirect file synchronization depending on the available connections.
3. **Output**: The script logs the status of the synchronization process, including success or failure for each step, and provides a log file for reference.

---

## **Hypothetical Input & Output Example**

### **Step 1: Script Starts and Prompts for Input**

The user runs the `sync.sh` script:

```bash
$ ./sync.sh
```

The script will prompt the user for the following information:

**Input**:
```bash
Enter source VM username: user1
Enter source VM IP: 192.168.1.10
Enter source VM SSH port (default: 22): 22
Enter destination VM username: user2
Enter destination VM IP: 192.168.2.20
Enter destination VM SSH port (default: 22): 22
Enter folder path to sync: /home/user1/documents
```

**Explanation**:
- **Source VM username**: The username on the source VM (e.g., `user1`).
- **Source VM IP**: The IP address of the source VM (e.g., `192.168.1.10`).
- **Destination VM username**: The username on the destination VM (e.g., `user2`).
- **Destination VM IP**: The IP address of the destination VM (e.g., `192.168.2.20`).
- **Folder to sync**: The folder path on the source VM that needs to be synchronized with the destination (e.g., `/home/user1/documents`).

### **Step 2: Script Tests SSH Connections**

The script checks if SSH connections can be established to both the source and destination VMs:

**Output**:
```bash
[2025-02-17 15:40:10] Checking SSH connections...

[2025-02-17 15:40:15] SSH connection to source VM (user1@192.168.1.10:22) successful.
[2025-02-17 15:40:16] SSH connection to destination VM (user2@192.168.2.20:22) successful.
```

**Explanation**: The script successfully connects to both the source and destination VMs.

---

### **Step 3: Check Direct Access Between Source and Destination**

The script checks if the source VM can directly access the destination VM via SSH:

**Output**:
```bash
[2025-02-17 15:40:18] Testing direct connection from source to destination...

[2025-02-17 15:40:19] Direct access available. Performing direct sync...
```

**Explanation**: Direct SSH access from the source to the destination is available, so the script will use `rsync` to perform the synchronization directly.

---

### **Step 4: Perform Direct Synchronization**

The script uses `rsync` to sync the folder from the source VM to the destination VM.

**Output**:
```bash
[2025-02-17 15:40:25] Step 1: Syncing from source VM to destination VM...

[2025-02-17 15:40:30] Sync completed successfully!
```

**Explanation**: The folder `/home/user1/documents` from the source VM is successfully synchronized to the destination VM.

---

### **Step 5: Final Output**

The script logs the completion of the synchronization process:

**Output**:
```bash
[2025-02-17 15:40:35] Sync operation completed!

Log file: /home/user1/sync_20250217.log
```

**Explanation**: The synchronization process is completed. The log file stores a record of all operations performed.

---

### **Hypothetical Error Example**

If SSH access to the destination VM is not possible, the script will output an error:

**Input**:
```bash
Enter destination VM username: user2
Enter destination VM IP: 192.168.3.20
```

**Output**:
```bash
[2025-02-17 15:45:22] Checking SSH connections...

[2025-02-17 15:45:23] ERROR: Cannot connect to destination VM (user2@192.168.3.20:22)
```

This error indicates that the destination VM cannot be reached via SSH, and the synchronization process will be halted.

---

### **Indirect Sync (If No Direct Access)**

If there is no direct access between the source and destination VMs, the script will proceed with indirect synchronization using an intermediary VM. It first transfers the files to a temporary directory on the main VM, then from the main VM to the destination.

**Output (for Indirect Sync)**:
```bash
[2025-02-17 15:50:00] Direct access not available. Performing indirect sync through main VM...

[2025-02-17 15:50:05] Step 1: Copying from source to main VM...

[2025-02-17 15:50:10] Step 2: Copying from main VM to destination...

[2025-02-17 15:50:20] Indirect sync completed successfully!
```

**Explanation**: The files are temporarily stored on the main VM before being transferred to the destination VM.

