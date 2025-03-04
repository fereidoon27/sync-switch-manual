# **main.sh - Hypothetical Input & Output Example**

## **Purpose**
The `main.sh` script serves as a user-friendly interface for managing and running other scripts (`action.sh` and `sync.sh`). It allows the user to easily select which action they want to perform, either deploying actions on a remote VM or synchronizing folders between VMs.

## **Workflow Overview**

1. **Input**: The user is prompted to select an action.
2. **Action Execution**: The script executes the chosen action (either `action.sh` or `sync.sh`).
3. **Output**: The script provides status updates and guides the user through the process.

---

## **Hypothetical Input & Output Example**

### **Step 1: Script Starts and Presents Menu**

When the user runs `main.sh`:

```bash
$ ./main.sh
```

The script displays a menu of available actions:

**Output**:
```bash
========================================

Select the action you would like to perform:

1: Deploy action.sh
   - Remotely execute sequential actions on a target VM.
   - Logs the timestamps for each action to keep track of progress.

2: Synchronize with sync.sh
   - Sync a folder from a source VM to a destination VM.
   - Direct synchronization or via an intermediate machine if needed.

0: Exit - Terminate the main script.

========================================
```

**Explanation**: The user is presented with three options:
- **1**: Deploy `action.sh` to remotely execute a series of actions on a target VM.
- **2**: Run `sync.sh` to sync a folder between two VMs.
- **0**: Exit the script.

---

### **Step 2: User Selects an Action**

The user enters a choice, for example, to run `action.sh` (option 1).

**Input**:
```bash
Enter a number (0, 1, 2): 1
```

**Explanation**: The user has selected to deploy `action.sh`.

### **Step 3: Script Executes Selected Action**

The script proceeds to execute the chosen script. In this case, it will run `action.sh`:

**Output**:
```bash
Running action.sh...
```

The script then hands control over to `action.sh`, where the user will follow the prompts and execute the desired sequence of actions on the target VM.

---

### **Step 4: User Selects Synchronization (Alternate Option)**

Alternatively, if the user selects option 2 to run `sync.sh`:

**Input**:
```bash
Enter a number (0, 1, 2): 2
```

**Output**:
```bash
Running sync.sh...
```

The script then runs `sync.sh`, which will prompt the user for the necessary details to sync a folder between two VMs.

---

### **Step 5: Exit the Script**

If the user chooses to exit, the script will terminate with a goodbye message.

**Input**:
```bash
Enter a number (0, 1, 2): 0
```

**Output**:
```bash
Exiting Main Script. Goodbye!
```

---

## **Key Points to Note**

- **Menu-Based Navigation**: `main.sh` provides a simple interface where the user selects the action they wish to perform, either deploying actions on a remote VM or syncing folders between VMs.
- **Action Delegation**: Once the user selects an option, `main.sh` delegates the task to either `action.sh` or `sync.sh`, ensuring that each script runs in a controlled and sequential manner.
- **Logging**: Both `action.sh` and `sync.sh` handle their own logging, with the results and progress being logged to respective log files. 

---

### **Hypothetical Error Example**

If the user enters an invalid option, the script will prompt them again:

**Input**:
```bash
Enter a number (0, 1, 2): 3
```

**Output**:
```bash
Invalid choice. Please enter a valid number (0, 1, or 2).
```

The user will be given another chance to select a valid option.

