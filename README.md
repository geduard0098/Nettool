Nettool
A comprehensive Bash utility for network diagnostics, interface information, and subnetting calculations with automatic CSV export and MySQL database integration.

Description
Nettool is a professional-grade CLI script designed to automate common networking tasks and eliminate manual binary math. It allows users to test internet connectivity, view local network interface details (IP, Netmask, MAC), and perform complex subnetting. Inspired by NetworkChuck’s subnetting methodology, the tool can calculate network boundaries based on a required number of hosts or a specific count of subnetworks. To ensure data persistence, the script automatically logs every calculation to localized CSV files and provides a built-in engine to import those records into a MySQL database for centralized record-keeping.

Getting Started
Dependencies
OS: Linux (Ubuntu, Debian, Kali, CentOS) or Windows via WSL.

Shell: Bash v4.0 or higher.

Math Engine: bc (Basic Calculator) for subnetting arithmetic.

Network Tools: net-tools package for the ifconfig command.

Database: mysql-client for the database import functionality.

Installing
Clone the repository to your local machine:

git clone  <project url>

Navigate into the project directory:

cd <./path/to/the/project>

Grant execution permissions to the script:

chmod +x <./path/to/the/project>

Executing program
How to run the program:

Launch the script from your terminal.

bash nettool.sh

Step-by-step menu navigation:

Select [1] to verify your connection to the internet via ping.

Select [2] to see your local IP, Netmask, and MAC address.

Select [3] to subnet by number of Hosts. (Enter Base IP, Mask, and required host count).

Select [4] to subnet by number of Subnetworks. (Enter Base IP, Mask, and required subnet count).

Select [5] to migrate your CSV history to a MySQL database.

Help
ifconfig: command not found: Install the net-tools package.

Subnetting math fails: Ensure the basic calculator is installed.

Database Import: Ensure your MySQL service is running and accessible before attempting the import.

Authors
[Georgescu Eduard-Gabriel]

GitHub: [@geduard0098]

Email: [eduard.georgescu0098@gmail.com]

Version History
0.3

Added MySQL database integration logic.

Implemented automatic CSV export for Hosts and Subnetworks.

Added duplicate check to prevent redundant CSV entries.

0.2

Added Subnetting functionality (by Hosts and by Subnetwork count).

Integrated binary mask visualization.

0.1

Initial Release: Basic connectivity test and interface info display.

License
This project is licensed under the MIT License - see the LICENSE.md file for details.

Acknowledgments
NetworkChuck: Inspiration and logic based on his subnetting series including "Subnetting my coffee shop" "Subnetting... but in reverse" and "Do you still suck at subnetting??"

LLM Assistance: The creation and optimization of this script were supported by advanced Prompt Engineering techniques using Large Language Models, specifically ChatGPT and Gemini, to ensure robust logic and clean code structure.