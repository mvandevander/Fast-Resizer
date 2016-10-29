#TODO: NEED TO FEED IN A LIST AS THE ARGUMENT TO THE FUNCTION HERE
#SO GET THE WHOLE LIST SPLIT UP AND FED INTO ONE PER THREAD
#TODO: Make it to where originals are only backed up if the image has to be resized

#this custom FolderBrowser came from https://www.sapien.com/forums/viewtopic.php?t=8662 via http://www.lyquidity.com/devblog/?p=136
Function BuildDialog {
	$sourcecode = @"
using System;
using System.Windows.Forms;
using System.Reflection;
namespace FolderSelect
{
	public class FolderSelectDialog
	{
		System.Windows.Forms.OpenFileDialog ofd = null;
		public FolderSelectDialog()
		{
			ofd = new System.Windows.Forms.OpenFileDialog();
			ofd.Filter = "Folders|\n";
			ofd.AddExtension = false;
			ofd.CheckFileExists = false;
			ofd.DereferenceLinks = true;
			ofd.Multiselect = false;
		}
		public string InitialDirectory
		{
			get { return ofd.InitialDirectory; }
			set { ofd.InitialDirectory = value == null || value.Length == 0 ? Environment.CurrentDirectory : value; }
		}
		public string Title
		{
			get { return ofd.Title; }
			set { ofd.Title = value == null ? "Select a folder" : value; }
		}
		public string FileName
		{
			get { return ofd.FileName; }
		}
		public bool ShowDialog()
		{
			return ShowDialog(IntPtr.Zero);
		}
		public bool ShowDialog(IntPtr hWndOwner)
		{
			bool flag = false;

			if (Environment.OSVersion.Version.Major >= 6)
			{
				var r = new Reflector("System.Windows.Forms");
				uint num = 0;
				Type typeIFileDialog = r.GetType("FileDialogNative.IFileDialog");
				object dialog = r.Call(ofd, "CreateVistaDialog");
				r.Call(ofd, "OnBeforeVistaDialog", dialog);
				uint options = (uint)r.CallAs(typeof(System.Windows.Forms.FileDialog), ofd, "GetOptions");
				options |= (uint)r.GetEnum("FileDialogNative.FOS", "FOS_PICKFOLDERS");
				r.CallAs(typeIFileDialog, dialog, "SetOptions", options);
				object pfde = r.New("FileDialog.VistaDialogEvents", ofd);
				object[] parameters = new object[] { pfde, num };
				r.CallAs2(typeIFileDialog, dialog, "Advise", parameters);
				num = (uint)parameters[1];
				try
				{
					int num2 = (int)r.CallAs(typeIFileDialog, dialog, "Show", hWndOwner);
					flag = 0 == num2;
				}
				finally
				{
					r.CallAs(typeIFileDialog, dialog, "Unadvise", num);
					GC.KeepAlive(pfde);
				}
			}
			else
			{
				var fbd = new FolderBrowserDialog();
				fbd.Description = this.Title;
				fbd.SelectedPath = this.InitialDirectory;
				fbd.ShowNewFolderButton = false;
				if (fbd.ShowDialog(new WindowWrapper(hWndOwner)) != DialogResult.OK) return false;
				ofd.FileName = fbd.SelectedPath;
				flag = true;
			}
			return flag;
		}
	}
	public class WindowWrapper : System.Windows.Forms.IWin32Window
	{
		public WindowWrapper(IntPtr handle)
		{
			_hwnd = handle;
		}
		public IntPtr Handle
		{
			get { return _hwnd; }
		}

		private IntPtr _hwnd;
	}
	public class Reflector
	{
		string m_ns;
		Assembly m_asmb;
		public Reflector(string ns)
			: this(ns, ns)
		{ }
		public Reflector(string an, string ns)
		{
			m_ns = ns;
			m_asmb = null;
			foreach (AssemblyName aN in Assembly.GetExecutingAssembly().GetReferencedAssemblies())
			{
				if (aN.FullName.StartsWith(an))
				{
					m_asmb = Assembly.Load(aN);
					break;
				}
			}
		}
		public Type GetType(string typeName)
		{
			Type type = null;
			string[] names = typeName.Split('.');

			if (names.Length > 0)
				type = m_asmb.GetType(m_ns + "." + names[0]);

			for (int i = 1; i < names.Length; ++i) {
				type = type.GetNestedType(names[i], BindingFlags.NonPublic);
			}
			return type;
		}
		public object New(string name, params object[] parameters)
		{
			Type type = GetType(name);
			ConstructorInfo[] ctorInfos = type.GetConstructors();
			foreach (ConstructorInfo ci in ctorInfos) {
				try {
					return ci.Invoke(parameters);
				} catch { }
			}

			return null;
		}
		public object Call(object obj, string func, params object[] parameters)
		{
			return Call2(obj, func, parameters);
		}
		public object Call2(object obj, string func, object[] parameters)
		{
			return CallAs2(obj.GetType(), obj, func, parameters);
		}
		public object CallAs(Type type, object obj, string func, params object[] parameters)
		{
			return CallAs2(type, obj, func, parameters);
		}
		public object CallAs2(Type type, object obj, string func, object[] parameters) {
			MethodInfo methInfo = type.GetMethod(func, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
			return methInfo.Invoke(obj, parameters);
		}
		public object Get(object obj, string prop)
		{
			return GetAs(obj.GetType(), obj, prop);
		}
		public object GetAs(Type type, object obj, string prop) {
			PropertyInfo propInfo = type.GetProperty(prop, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
			return propInfo.GetValue(obj, null);
		}
		public object GetEnum(string typeName, string name) {
			Type type = GetType(typeName);
			FieldInfo fieldInfo = type.GetField(name);
			return fieldInfo.GetValue(null);
		}
	}
}
"@
#The original script also included the assembly 'System.Reflection here
#	$assemblies = ('System.Windows.Forms', 'System.Reflection')
	$assemblies = ('System.Windows.Forms')
	Add-Type -TypeDefinition $sourceCode -ReferencedAssemblies $assemblies -ErrorAction STOP
}


Function Get-FileName($initialDirectory)
{
    $fsd = New-Object FolderSelect.FolderSelectDialog
    $fsd.Title = "Select the job folder that you want resized";
    $fsd.InitialDirectory = $initialDirectory
    $fsd.ShowDialog() | Out-Null
    return $fsd.FileName
}

function DoMultiThreaded {

#.Synopsis
#    This is a quick and open-ended script multi-threader searcher
#    
#.Description
#    This script will allow any general, external script to be multithreaded by providing a single
#    argument to that script and opening it in a seperate thread.  It works as a filter in the 
#    pipeline, or as a standalone script.  It will read the argument either from the pipeline
#    or from a filename provided.  It will send the results of the child script down the pipeline,
#    so it is best to use a script that returns some sort of object.
#
#    Authored by Ryan Witschger - http://www.Get-Blog.com
#    
#.PARAMETER Command
#    This is where you provide the PowerShell Cmdlet / Script file that you want to multithread.  
#    You can also choose a built in cmdlet.  Keep in mind that your script.  This script is read into 
#    a scriptblock, so any unforeseen errors are likely caused by the conversion to a script block.
#    
#.PARAMETER ObjectList
#    The objectlist represents the arguments that are provided to the child script.  This is an open ended
#    argument and can take a single object from the pipeline, an array, a collection, or a file name.  The 
#    multithreading script does it's best to find out which you have provided and handle it as such.  
#    If you would like to provide a file, then the file is read with one object on each line and will 
#    be provided as is to the script you are running as a string.  If this is not desired, then use an array.
#    
#.PARAMETER InputParam
#    This allows you to specify the parameter for which your input objects are to be evaluated.  As an example, 
#    if you were to provide a computer name to the Get-Process cmdlet as just an argument, it would attempt to 
#    find all processes where the name was the provided computername and fail.  You need to specify that the 
#    parameter that you are providing is the "ComputerName".
#
#.PARAMETER AddParam
#    This allows you to specify additional parameters to the running command.  For instance, if you are trying
#    to find the status of the "BITS" service on all servers in your list, you will need to specify the "Name"
#    parameter.  This command takes a hash pair formatted as follows:  
#
#    @{"ParameterName" = "Value"}
#    @{"ParameterName" = "Value" ; "ParameterTwo" = "Value2"}
#
#.PARAMETER AddSwitch
#    This allows you to add additional switches to the command you are running.  For instance, you may want 
#    to include "RequiredServices" to the "Get-Service" cmdlet.  This parameter will take a single string, or 
#    an aray of strings as follows:
#
#    "RequiredServices"
#    @("RequiredServices", "DependentServices")
#
#.PARAMETER MaxThreads
#    This is the maximum number of threads to run at any given time.  If resources are too congested try lowering
#    this number.  The default value is 20.
#    
#.PARAMETER SleepTimer
#    This is the time between cycles of the child process detection cycle.  The default value is 200ms.  If CPU 
#    utilization is high then you can consider increasing this delay.  If the child script takes a long time to
#    run, then you might increase this value to around 1000 (or 1 second in the detection cycle).
#
#    
#.EXAMPLE
#    Both of these will execute the script named ServerInfo.ps1 and provide each of the server names in AllServers.txt
#    while providing the results to the screen.  The results will be the output of the child script.
#    
#    gc AllServers.txt | .\Run-CommandMultiThreaded.ps1 -Command .\ServerInfo.ps1
#    .\Run-CommandMultiThreaded.ps1 -Command .\ServerInfo.ps1 -ObjectList (gc .\AllServers.txt)
#
#.EXAMPLE
#    The following demonstrates the use of the AddParam statement
#    
#    $ObjectList | .\Run-CommandMultiThreaded.ps1 -Command "Get-Service" -InputParam ComputerName -AddParam @{"Name" = "BITS"}
#    
#.EXAMPLE
#    The following demonstrates the use of the AddSwitch statement
#    
#    $ObjectList | .\Run-CommandMultiThreaded.ps1 -Command "Get-Service" -AddSwitch @("RequiredServices", "DependentServices")
#
#.EXAMPLE
#    The following demonstrates the use of the script in the pipeline
#    
#    $ObjectList | .\Run-CommandMultiThreaded.ps1 -Command "Get-Service" -InputParam ComputerName -AddParam @{"Name" = "BITS"} | Select Status, MachineName
#


Param([Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]$ObjectList,
    $InputParam = $Null,
    $MaxThreads = 16,
    $SleepTimer = 33,
    $MaxResultTime = 120,
    [HashTable]$AddParam = @{},
    [Array]$AddSwitch = @()
)

Begin{
    $ISS = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $ISS, $Host)
    $RunspacePool.Open()
        $OFS = "`r`n"
        $Code = {
                    Param ( [Parameter(Mandatory=$True)] [ValidateNotNull()] $filelist)
                    ForEach ($filename in $filelist)
                    {
                        $imgItem = Get-Item $filename
                        $backupName = ($imgItem.DirectoryName + "\original\" + $imgItem.Name)
                        if((Test-Path($backupName)) -eq $False ) {
                            Copy-Item $imgItem.FullName $backupName
                        }
                        $hash = (Get-Random -minimum 100000 -maximum 999999)
                        $imageTarget = $filename.Substring(0, $filename.Length - 4) + "_resized_" + $hash + ".jpg"
                        $quality = 100
 
                        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
                        $bmp = [System.Drawing.Image]::FromFile($filename)
 
                        #hardcoded canvas size...
                        $canvasTargetSize = 3000.0

                        if(($bmp.Width) -le $canvasTargetSize) {if(($bmp.Height) -le $canvasTargetSize) {return}}
 
                        #Encoder parameter for image quality
                        $myEncoder = [System.Drawing.Imaging.Encoder]::Quality
                        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
                        $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($myEncoder, 100)
                        # get codec
                        $myImageCodecInfo = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|where {$_.MimeType -eq 'image/jpeg'}
 
                        #compute the final ratio to use
                        $ratioX = $canvasTargetSize / $bmp.Width;
                        $ratioY = $canvasTargetSize / $bmp.Height;
                        $ratio = $ratioY
                        if($ratioX -le $ratioY){
                            $ratio = $ratioX
                        }
 
                        #create resized bitmap
                        $newWidth = [int] ($bmp.Width*$ratio)
                        $newHeight = [int] ($bmp.Height*$ratio)
                        $bmpResized = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
                        $graph = [System.Drawing.Graphics]::FromImage($bmpResized)
 
                        $graph.Clear([System.Drawing.Color]::White)
                        $graph.DrawImage($bmp,0,0 , $newWidth, $newHeight)
 
                        #save to file
                        $bmpResized.Save($imageTarget,$myImageCodecInfo, $($encoderParams))
                        $bmpResized.Dispose()
                        $bmp.Dispose()
                        Remove-Item $filename
                        Rename-Item $imageTarget $filename
                    }
                    
        }
        Remove-Variable OFS
    $Jobs = @()
}

Process{
    Write-Progress -Activity "Preloading threads" -Status "Starting Job $($jobs.count)"

    $totalObjects = $ObjectList.Length
    $numberOfBuckets = 16
    $baseamount = [Math]::Floor(($totalObjects/$numberOfBuckets))
    $a = New-Object System.Collections.ArrayList
    $a.Add($ObjectList[0..$baseamount]) > $null
    for($i = 1; (($i) -lt $numberOfBuckets); $i++)
    {
        $start = ($i * $baseamount) + 1 
        $end = $start + $baseamount
        $end = [Math]::Min($end, ($ObjectList.Length-1))
        #$a += $ObjectList[$start..$end]
        $a.Add($ObjectList[$start..$end]) > $null
    }
    ForEach ($List in $a)
    {

            $PowershellThread = [powershell]::Create().AddScript($Code)
            $PowershellThread.AddArgument(($List)) | out-null
            $PowershellThread.RunspacePool = $RunspacePool
            $Handle = $PowershellThread.BeginInvoke()
            $Job = "" | Select-Object Handle, Thread, object
            $Job.Handle = $Handle
            $Job.Thread = $PowershellThread
           # $Job.Object = "1"
            $Jobs += $Job
    }
        
}

End{
    $ResultTimer = Get-Date
    While (@($Jobs | Where-Object {$_.Handle -ne $Null}).count -gt 0)  {
    
        $Remaining = "$($($Jobs | Where-Object {$_.Handle.IsCompleted -eq $False}).object)"
        If ($Remaining.Length -gt 60){
            $Remaining = $Remaining.Substring(0,60) + "..."
        }
        Write-Progress `
            -Activity "Waiting for Jobs - $($MaxThreads - $($RunspacePool.GetAvailableRunspaces())) of $MaxThreads threads running" `
            -PercentComplete (($Jobs.count - $($($Jobs | Where-Object {$_.Handle.IsCompleted -eq $False}).count)) / $Jobs.Count * 100) `
            -Status "$(@($($Jobs | Where-Object {$_.Handle.IsCompleted -eq $False})).count) remaining - $remaining" 

        ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
            $Job.Thread.EndInvoke($Job.Handle)
            $Job.Thread.Dispose()
            $Job.Thread = $Null
            $Job.Handle = $Null
            $ResultTimer = Get-Date
        }
        If (($(Get-Date) - $ResultTimer).totalseconds -gt $MaxResultTime){
            Write-Error "Child script appears to be frozen, try increasing MaxResultTime"
            Exit
        }
        Start-Sleep -Milliseconds $SleepTimer
        
    } 
    $RunspacePool.Close() | Out-Null
    $RunspacePool.Dispose() | Out-Null
} 
}
BuildDialog

[string] $inputfolder = (Get-FileName 'Y:\Jobs')
if(($inputfolder) -eq "Cancel")
{
    Write-Host("ERROR: User must pick a directory to resize")
    return
}
if(($inputfolder) -eq ""){
Write-Host("ERROR: User must pick a directory to resize")
return
}
Write-Host("Processing directory: " + $inputfolder)
$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
$originalFolder = (($inputfolder) + "\original")


if((Test-Path $originalFolder) -eq $false) {
    New-Item $originalFolder -type directory -Force | Out-Null
}

$filelist = $(Get-ChildItem ($inputfolder + '\*') -Include *.jpg, *.jpeg ).FullName
if($filelist -eq $null) {
    Write-Host "ERROR: No images found in directory"
    Return
}

DoMultiThreaded -ObjectList $filelist
Write-Output "Done processing! Elapsed Time: $($elapsed.Elapsed.ToString())"
Start-Sleep 4