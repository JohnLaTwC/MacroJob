'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
' Proof-of-concept by @JohnLaTwC
' December 2016
'
' This is for learning purposes only. It is not secure. It is not complete.
' It is provided as a way to learn about Windows Security mechanisms.
'
' Macro malware was all the rage in the 1990s (just ask @VessOnSecurity) and now they are back
' with a vengeance (https://twitter.com/JohnLaTwC/status/775689864389931008).
' So it is only appropriate to use 1990s technology to fight 1990s threats.
'
' The idea here is that most malicious Word macro files lure the user to 'Enable Content'
' or 'Enable Macros' and then launch another program in the background to run a payload.
' By blocking the ability for Word to launch other processes, many commodity malware samples
' will fail.
'
' This proof-of-concept calls the Win32 APIs for Windows Job Objects. Job objects were introduced in
' Windows 2000.  Here is an article from 1999 by Jeffrey Richter on them:
'       https://www.microsoft.com/msj/0399/jobkernelobj/jobkernelobj.aspx
'
' Job objects allow you to place many different restrictions on processes.
' This poc tests to see if Word is opening a file in the temp folder outside of the protected view,
' and if so, it places the Word process in a job that prevents it from creating child processes using
' the JOB_OBJECT_LIMIT_ACTIVE_PROCESS option.
'
' You can learn more about job objects here:
' https://msdn.microsoft.com/en-us/library/windows/desktop/ms684161(v=vs.85).aspx
'
' Channel your inner @tiraniddo to learn about Windows security primitives and then
' then figure out how to bypass them
'
Option Explicit
Private Type LARGE_INTEGER
    lowPart As Long
    highPart As Long
End Type

Private Type JOBOBJECT_BASIC_LIMIT_INFORMATION
    PerProcessUserTimeLimit As LARGE_INTEGER
    PerJobUserTimeLimit As LARGE_INTEGER
    LimitFlags As Long
    MinimumWorkingSetSize As Long
    MaximumWorkingSetSize As Long
    ActiveProcessLimit As Long
    ByteArray(15) As Byte
End Type
Declare Function CreateJobObjectA Lib "kernel32" (ByVal lpJobAttributes As Long, ByVal lpName As String) As Long

Declare Function SetInformationJobObject Lib "kernel32" (ByVal hJob As Long, ByVal JobObjectInfoClass As Long, ByRef lpJobObjectInfo As JOBOBJECT_BASIC_LIMIT_INFORMATION, ByVal cbJobObjectInfoLength As Long) As Boolean

Declare Function AssignProcessToJobObject Lib "kernel32" (ByVal hJob As Long, ByVal hProcess As Long) As Boolean

Declare Function GetLastError Lib "kernel32" () As Long

Declare Function GetCurrentProcessId Lib "kernel32" () As Long

Declare Function CloseHandle Lib "kernel32" (ByVal hObject As Long) As Boolean

Declare Function FlashWindow Lib "user32" (ByVal hwnd As Long, ByVal bInvert As Long) As Long

Declare Function GetForegroundWindow Lib "user32" () As Long

Dim g_fAddedToJob
Declare Function GetCommandLineA Lib "kernel32" () As Long
Declare Function lstrcpynA Lib "kernel32" (ByVal pDestination As String, ByVal pSource As Long, ByVal iMaxLength As Integer) As Long
Dim g_szCmdLine
Dim g_fHookOnClose
Sub AddProcessToJob()
    Dim dwLastErr
    Dim hJob
    Const JobObjectBasicLimitInformation = 2
    Const JOB_OBJECT_LIMIT_ACTIVE_PROCESS = &H8
    Dim fRetVal
    
    If g_fAddedToJob Then
        Exit Sub
        
    'Define restrictions
    ' JOB_OBJECT_LIMIT_ACTIVE_PROCESS prevents the app from spawning child processes
    Dim limitInfo As JOBOBJECT_BASIC_LIMIT_INFORMATION
    limitInfo.LimitFlags = JOB_OBJECT_LIMIT_ACTIVE_PROCESS
    limitInfo.ActiveProcessLimit = 1    ' Set to 1 means no child processes
    
    'Create the job object
    hJob = CreateJobObjectA(0, "MacroJob_" & GetCurrentProcessId)
    
    If hJob <> 0 Then
        'Apply the restrictions
        If SetInformationJobObject(hJob, JobObjectBasicLimitInformation, limitInfo, Len(limitInfo)) <> 0 Then
        
            'Add the current process (-1) to the Job
            If AssignProcessToJobObject(hJob, -1) <> 0 Then
                'Flash window to indicate success
                FlashWindow GetForegroundWindow(), 1
                g_fAddedToJob = True
            Else
                dwLastErr = GetLastError()
                MsgBox ("Error calling AssignProcessToJobObject= " & dwLastErr)
            End If
        Else
            dwLastErr = GetLastError()
            MsgBox ("Error calling SetInformationJobObject= " & dwLastErr)
        End If
        CloseHandle (hJob)
    End If
End Sub

Function GetCommandLine()
    If Len(g_szCmdLine) = 0 Then
        Dim pCmdLine As Long
        Dim strCmdLine As String
        pCmdLine = GetCommandLineA()
        strCmdLine = String$(300, vbNullChar)
        lstrcpynA strCmdLine, pCmdLine, Len(strCmdLine)
        g_szCmdLine = Left(strCmdLine, InStr(1, strCmdLine, vbNullChar) - 1)
    End If
    GetCommandLine = g_szCmdLine
End Function
Sub AutoExec()
    g_fHookOnClose = False
    
    ' If the file has the mark of the web, then it will be opened in the Protected Viewer
    ' Word spawns Word as a child process in a sandbox. If the user is going to enable macros, then the
    ' viewer closes the sandbox process and re-opens the doc in the parent Word process.
    ' Put the parent in a job after the child has closed.
    If HasMOTW() Then
        g_fHookOnClose = True
    Else
        AutoExecImpl
    End If
End Sub

Sub AutoClose()
    If g_fHookOnClose Then
        AutoExecImpl
    End If
End Sub
'   Given: "C:\Program Files (x86)\Microsoft Office\Root\Office16\WINWORD.EXE" /n "C:\Users\user1\AppData\Local\Microsoft\Windows\INetCache\Content.Outlook\E6T14OYH\filename.doc"
'   return: C:\Users\user1\AppData\Local\Microsoft\Windows\INetCache\Content.Outlook\E6T14OYH\filename.doc
Function GetFileName()
    Dim szFilePath: szFilePath = ""
    Dim idx1: idx1 = InStr(5, GetCommandLine(), ":\", vbTextCompare)    ' start at 5 to skip past drive letter on Word itself
    If idx1 > 0 Then
        idx1 = idx1 - 1  'get drive letter
         Dim idx2: idx2 = InStr(idx1, GetCommandLine(), """", vbTextCompare)
         If idx2 > 0 Then
             szFilePath = Trim(Mid(GetCommandLine(), idx1, idx2 - idx1))
             szFilePath = Replace(szFilePath, """", "") 'remove any quotes
         End If
     End If
     GetFileName = szFilePath
End Function
' Return True if the document has the Mark of the Web on the file (i.e. sent from external user)
Function HasMOTW()
    If CreateObject("Scripting.FileSystemObject").FileExists(GetFileName & ":Zone.Identifier") Then
        ' See Joe Security blog linked here on Zone.Identifier: https://twitter.com/joe4security/status/773523575106105345
        HasMOTW = True
    Else
        HasMOTW = False
    End If
End Function
Sub AutoExecImpl()
    ' If the file was downloaded to a temp folder...
    If InStr(1, GetCommandLine(), "\Content.Outlook\", vbTextCompare) > 1 Or _
       InStr(1, GetCommandLine(), "\Temp\", vbTextCompare) > 1 Or _
       InStr(1, GetCommandLine(), "\Downloads\", vbTextCompare) > 1 Then
        AddProcessToJob
    End If
End Sub
=======
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
' Proof-of-concept by @JohnLaTwC
' December 2016
'
' This is for learning purposes only. It is not secure. It is not complete.
' It is provided as a way to learn about Windows Security mechanisms.
'
' Macro malware was all the rage in the 1990s (just ask @VessOnSecurity) and now they are back
' with a vengeance (https://twitter.com/JohnLaTwC/status/775689864389931008).
' So it is only appropriate to use 1990s technology to fight 1990s threats.
'
' The idea here is that most malicious Word macro files lure the user to 'Enable Content'
' or 'Enable Macros' and then launch another program in the background to run a payload.
' By blocking the ability for Word to launch other processes, many commodity malware samples
' will fail.
'
' This proof-of-concept calls the Win32 APIs for Windows Job Objects. Job objects were introduced in
' Windows 2000.  Here is an article from 1999 by Jeffrey Richter on them:
'       https://www.microsoft.com/msj/0399/jobkernelobj/jobkernelobj.aspx
'
' Job objects allow you to place many different restrictions on processes.
' This poc tests to see if Word is opening a file in the temp folder outside of the protected view,
' and if so, it places the Word process in a job that prevents it from creating child processes using
' the JOB_OBJECT_LIMIT_ACTIVE_PROCESS option.
'
' You can learn more about job objects here:
' https://msdn.microsoft.com/en-us/library/windows/desktop/ms684161(v=vs.85).aspx
'
' Channel your inner @tiraniddo to learn about Windows security primitives and then
' then figure out how to bypass them
'
Option Explicit
Private Type LARGE_INTEGER
    lowPart As Long
    highPart As Long
End Type

Private Type JOBOBJECT_BASIC_LIMIT_INFORMATION
    PerProcessUserTimeLimit As LARGE_INTEGER
    PerJobUserTimeLimit As LARGE_INTEGER
    LimitFlags As Long
    MinimumWorkingSetSize As Long
    MaximumWorkingSetSize As Long
    ActiveProcessLimit As Long
    ByteArray(15) As Byte
End Type
Declare Function CreateJobObjectA Lib "kernel32" (ByVal lpJobAttributes As Long, ByVal lpName As String) As Long

Declare Function SetInformationJobObject Lib "kernel32" (ByVal hJob As Long, ByVal JobObjectInfoClass As Long, ByRef lpJobObjectInfo As JOBOBJECT_BASIC_LIMIT_INFORMATION, ByVal cbJobObjectInfoLength As Long) As Boolean

Declare Function AssignProcessToJobObject Lib "kernel32" (ByVal hJob As Long, ByVal hProcess As Long) As Boolean

Declare Function GetLastError Lib "kernel32" () As Long

Declare Function GetCurrentProcessId Lib "kernel32" () As Long

Declare Function CloseHandle Lib "kernel32" (ByVal hObject As Long) As Boolean

Declare Function FlashWindow Lib "user32" (ByVal hwnd As Long, ByVal bInvert As Long) As Long

Declare Function GetForegroundWindow Lib "user32" () As Long
'Private Declare Function CloseHandle Lib "kernel32" (ByVal hObject As Long) As Boolean

Dim g_fAddedToJob
Declare Function GetCommandLineA Lib "kernel32" () As Long
Declare Function lstrcpynA Lib "kernel32" (ByVal pDestination As String, ByVal pSource As Long, ByVal iMaxLength As Integer) As Long
Dim g_cAutoOpenCallCount
Dim g_cProtectedViewWindows
Dim g_szCmdLine
Dim g_fHookOnClose
Sub AddProcessToJob()
    Dim dwLastErr
    Dim hJob
    Const JobObjectBasicLimitInformation = 2
    Const JOB_OBJECT_LIMIT_ACTIVE_PROCESS = &H8
    Dim fRetVal
    
    'Define restrictions
    ' JOB_OBJECT_LIMIT_ACTIVE_PROCESS prevents the app from spawning child processes
    Dim limitInfo As JOBOBJECT_BASIC_LIMIT_INFORMATION
    limitInfo.LimitFlags = JOB_OBJECT_LIMIT_ACTIVE_PROCESS
    limitInfo.ActiveProcessLimit = 1    ' Set to 1 means no child processes
    
    'Create the job object
    hJob = CreateJobObjectA(0, "MacroJob_" & GetCurrentProcessId)
    
    If hJob <> 0 Then
        'Apply the restrictions
        If SetInformationJobObject(hJob, JobObjectBasicLimitInformation, limitInfo, Len(limitInfo)) <> 0 Then
        
            'Add the current process (-1) to the Job
            If AssignProcessToJobObject(hJob, -1) <> 0 Then
                'Flash window to indicate success
                FlashWindow GetForegroundWindow(), 1
                g_fAddedToJob = True
            Else
                dwLastErr = GetLastError()
                MsgBox ("Error calling AssignProcessToJobObject= " & dwLastErr)
            End If
        Else
            dwLastErr = GetLastError()
            MsgBox ("Error calling SetInformationJobObject= " & dwLastErr)
        End If
        CloseHandle (hJob)
    End If
End Sub

Function GetCommandLine()
    If Len(g_szCmdLine) = 0 Then
        Dim pCmdLine As Long
        Dim strCmdLine As String
        pCmdLine = GetCommandLineA()
        strCmdLine = String$(300, vbNullChar)
        lstrcpynA strCmdLine, pCmdLine, Len(strCmdLine)
        g_szCmdLine = Left(strCmdLine, InStr(1, strCmdLine, vbNullChar) - 1)
    End If
    GetCommandLine = g_szCmdLine
End Function
Sub AutoExec()
    g_fHookOnClose = False
    
    ' If the file has the mark of the web, then it will be opened in the Protected Viewer
    ' Word spawns Word as a child process in a sandbox. If the user is going to enable macros, then the
    ' viewer closes the sandbox process and re-opens the doc in the parent Word process.
    ' Put the parent in a job after the child has closed.
    If HasMOTW() Then
        g_fHookOnClose = True
    Else
        AutoExecImpl
    End If
End Sub

Sub AutoClose()
    If g_fHookOnClose Then
        AutoExecImpl
    End If
End Sub
'   Given: "C:\Program Files (x86)\Microsoft Office\Root\Office16\WINWORD.EXE" /n "C:\Users\user1\AppData\Local\Microsoft\Windows\INetCache\Content.Outlook\E6T14OYH\filename.doc"
'   return: C:\Users\user1\AppData\Local\Microsoft\Windows\INetCache\Content.Outlook\E6T14OYH\filename.doc
Function GetFileName()
    Dim szFilePath: szFilePath = ""
    Dim idx1: idx1 = InStr(5, GetCommandLine(), ":\", vbTextCompare)    ' start at 5 to skip past drive letter on Word itself
    If idx1 > 0 Then
        idx1 = idx1 - 1  'get drive letter
         Dim idx2: idx2 = InStr(idx1, GetCommandLine(), """", vbTextCompare)
         If idx2 > 0 Then
             szFilePath = Trim(Mid(GetCommandLine(), idx1, idx2 - idx1))
             szFilePath = Replace(szFilePath, """", "") 'remove any quotes
         End If
     End If
     GetFileName = szFilePath
End Function
' Return True if the document has the Mark of the Web on the file (i.e. sent from external user)
Function HasMOTW()
    If CreateObject("Scripting.FileSystemObject").FileExists(GetFileName & ":Zone.Identifier") Then
        ' See Joe Security blog linked here on Zone.Identifier: https://twitter.com/joe4security/status/773523575106105345
        HasMOTW = True
    Else
        HasMOTW = False
    End If
End Function
Sub AutoExecImpl()
    ' If the file was downloaded to a temp folder...
    If InStr(1, GetCommandLine(), "\Content.Outlook\", vbTextCompare) > 1 Or _
       InStr(1, GetCommandLine(), "\Temp\", vbTextCompare) > 1 Or _
       InStr(1, GetCommandLine(), "\Downloads\", vbTextCompare) > 1 Then
        AddProcessToJob
    End If
End Sub
