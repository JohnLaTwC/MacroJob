MacroJob
=============
Proof-of-concept by @JohnLaTwC
December 2016
This is for learning purposes only. It is not secure. It is not complete.
It is provided as a way to learn about Windows Security mechanisms.

Macro malware was all the rage in the 1990s (just ask @VessOnSecurity) and now they are back 
with a vengeance (https://twitter.com/JohnLaTwC/status/775689864389931008).
So it is only appropriate to use 1990s technology to fight 1990s threats.

The idea here is that most malicious Word macro files lure the user to 'Enable Content'
or 'Enable Macros' and then launch another program in the background to run a payload.
By blocking the ability for Word to launch other processes, many commodity malware samples
will fail.

This proof-of-concept calls the Win32 APIs for Windows Job Objects. Job objects were introduced in
Windows 2000.  Here is an article from 1999 by Jeffrey Richter on them:
https://www.microsoft.com/msj/0399/jobkernelobj/jobkernelobj.aspx

Job objects allow you to place many different restrictions on processes.
This poc uses the JOB_OBJECT_LIMIT_ACTIVE_PROCESS option to limit child processes.
You can learn more about job objects here:
https://msdn.microsoft.com/en-us/library/windows/desktop/ms684161(v=vs.85).aspx

Channel your inner @tiraniddo to learn about Windows security primitives and 
figure out how to bypass them, then develop a countermeasure :)

INSTALL: 
-------
   1. Launch Word, New Blank Document
   2. From the View ribbon tab, click Macros (Alt + F8)
   3. Select Normal.dotm (global template) from 'Macros in:' combobox
   4. Type 'test' as the macro name and click Create. This will bring up the VBA editor
   5. Paste in these macros. 
   6. Save and exit Word
