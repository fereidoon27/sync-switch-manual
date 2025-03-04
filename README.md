

# **VM Management Scripts**

VM Management Scripts for Action Execution and File Synchronization

## **Description**
This repository contains a collection of shell scripts designed for automating actions on remote Virtual Machines (VMs). The key functionalities include:

1. **Action Execution (action.sh)**: Remotely execute a series of predefined actions (e.g., file creation) on a target VM, with logging of timestamps and results.
2. **File Synchronization (sync.sh)**: Synchronize a specified folder from a source VM to a destination VM, either directly or through an intermediary VM.
3. **Main Script (main.sh)**: A main menu-driven interface that allows users to choose between executing actions or performing synchronization.

These scripts are useful for managing remote VMs, automating tasks, and ensuring smooth file transfers between multiple VMs.

## **Installation Instructions**
### Prerequisites:
- **Linux or macOS** environment (for using bash).
- **SSH access** to both the source and destination VMs.
- **rsync** must be installed on both source and destination VMs for file synchronization.

### Setup Steps:
1. Clone the repository:
   ```bash
   git clone https://github.com/fereidoon27/vm-management-scripts.git
   cd vm-management-scripts
   ```

2. Make the scripts executable:
   ```bash
   chmod +x action.sh sync.sh main.sh
   ```

3. Ensure that SSH access is correctly set up for both the source and destination VMs. The scripts will ask for SSH credentials (username, IP, port) when executed.

## **Usage**
### Running the Main Script:
1. Start the script by running the following command:
   ```bash
   ./main.sh
   ```

2. **Menu Options:**
   - **Option 1: Deploy action.sh**
     - This will execute predefined actions (like creating text files) on a target VM.
     - You'll be asked to input the target VM’s SSH credentials and the folder where the actions will be performed.
     - The script logs timestamps for each action performed.

   - **Option 2: Synchronize with sync.sh**
     - This will synchronize a folder between a source VM and a destination VM.
     - It first checks if a direct SSH connection is possible between the source and destination. If not, it performs the sync via an intermediary VM.
     - The script uses `rsync` for the synchronization and logs each step.
   
   - **Option 0: Exit**
     - Exits the main menu and terminates the script.

### Example Workflow:
1. Run the `main.sh` script:
   ```bash
   ./main.sh
   ```
   
2. Select **1** to deploy `action.sh` and perform a series of actions on a target VM, or select **2** to synchronize files between VMs.

3. Follow the prompts to provide necessary SSH credentials, folder paths, and confirm actions.

## **Code Structure**
Here’s an overview of how the code is organized within the repository:

- **action.sh**: Handles remote execution of predefined actions (like creating files on the target VM). Logs actions and timestamps for auditing.
- **sync.sh**: Synchronizes a folder between a source and destination VM, checking SSH connections and using `rsync` for the file transfer.
- **main.sh**: Provides a user-friendly menu interface that lets users choose between running `action.sh` or `sync.sh`.



