# **action.sh - Hypothetical Input & Output Example**

## **Purpose**
The `action.sh` script allows the user to perform a series of predefined actions on a target VM via SSH. These actions include creating text files on the target VM, and logging the results along with timestamps for tracking.

## **Workflow Overview**

1. **Input**: The script prompts the user for SSH connection details (target VM's username, IP address, SSH port, and target folder).
2. **Action Execution**: The user selects a sequence of actions, such as creating text files with specific contents.
3. **Output**: The script logs the results, including success or failure for each action, and generates timestamp logs.

---

## **Hypothetical Input & Output Example**

### **Step 1: Script Starts and Prompts for Input**

The user runs the `action.sh` script:

```bash
$ ./action.sh
```

The script will prompt the user for the following information:

**Input**:
```bash
Enter target VM username: admin
Enter target VM IP: 192.168.1.100
Enter target VM SSH port (default: 22): 22
Enter target folder name (e.g., van-buren-bubbles-wallex): /home/admin/data
```

**Explanation**:
- **Target VM username**: The username on the remote VM (e.g., `admin`).
- **Target VM IP**: The IP address of the target VM (e.g., `192.168.1.100`).
- **Target folder**: The folder path on the target VM where files will be created.

### **Step 2: Script Connects via SSH**

The script attempts to connect to the target VM and logs the connection result.

**Output**:
```bash
[2025-02-17 15:35:22] Testing SSH connection...
[2025-02-17 15:35:23] SSH connection to 192.168.1.100:22 successful.
```

**Explanation**: The script successfully connects to the target VM via SSH.

---

### **Step 3: Display Available Actions**

The script then lists the available actions for the user to choose from:

**Output**:
```bash
Available actions:
1: Create newfile_1.txt (Write: (this is written by action 1 ))
2: Create newfile_2.txt (Write: (this is written by action 2 ))
3: Create newfile_3.txt (Write: (this is written by action 3 ))
4: Create newfile_4.txt (Write: (this is written by action 4 ))
```

### **Step 4: User Selects Action Sequence**

The user is asked to input a sequence of actions to perform, such as `12` (which means perform actions 1 and 2 in sequence).

**Input**:
```bash
Enter sequence of actions (2-4 digits, e.g., 12 or 1234): 12
```

**Explanation**: The user has selected to perform actions 1 and 2.

### **Step 5: Script Executes Selected Actions**

For each action in the sequence, the script logs the action's start time and executes it. For example, the script will create `newfile_1.txt` and `newfile_2.txt` on the target VM.

**Output** (Example for action 1):
```bash
Executing step 1 of 2: Action 1
[2025-02-17 15:36:01] Starting action 1: Create newfile_1.txt
[2025-02-17 15:36:02] Action 1 (Create newfile_1.txt) completed successfully
```

**Output** (Example for action 2):
```bash
Executing step 2 of 2: Action 2
[2025-02-17 15:36:05] Starting action 2: Create newfile_2.txt
[2025-02-17 15:36:06] Action 2 (Create newfile_2.txt) completed successfully
```

---

### **Step 6: Final Output**

After completing the sequence, the script displays a success message, logs the timestamp for each action, and outputs the location of the logs:

**Output**:
```bash
Sequence completed successfully!
Timestamp log: /home/admin/service_timestamps_20250217.log
Action log: /home/admin/service_actions_20250217.log
```

**Explanation**:
- The script successfully completed the sequence of actions.
- The **timestamp log** tracks the start and end time of each action.
- The **action log** tracks any errors or successes during the execution.

---

## **Key Points to Note**

- **Logging**: Every action performed is logged with a timestamp in both the `service_actions` and `service_timestamps` log files. These logs are crucial for tracking the progress and success/failure of actions.
- **Action Sequence**: The user can select a sequence of actions by entering a string of numbers (e.g., `12`, `123`), and the script will execute the actions in the order specified.

---

### **Hypothetical Error Example**

If an invalid folder path is provided, or the target folder does not exist, the script will output an error:

**Input**:
```bash
Enter target folder name (e.g., van-buren-bubbles-wallex): /home/admin/nonexistent_folder
```

**Output**:
```bash
ERROR: Folder '/home/admin/nonexistent_folder' does not exist on target VM
```

This ensures that the user is immediately aware of any issues with the folder path and can correct them before proceeding.

