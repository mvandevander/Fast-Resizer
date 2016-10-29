#TODO: Make it to where originals are only backed up if the image has to be resized
#TODO: Test to make sure there are no degenerate scenarios where images may not get resized, or may not get backed up


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
	$assemblies = ('System.Windows.Forms', 'System.Reflection')
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

$ScriptBlock = {
  param($filelist)

#Credit for this image resizing function should go to Benoit Patra
##original found at http://benoitpatra.com/2014/09/14/resize-image-and-preserve-ratio-with-powershell/

function MakePreviewImages
{
    Param ( [Parameter(Mandatory=$True)] [ValidateNotNull()] $imageSource,
    [Parameter(Mandatory=$True)] [ValidateNotNull()] $imageTarget,
    [Parameter(Mandatory=$true)][ValidateNotNull()] $quality )
 
    if (!(Test-Path $imageSource)){throw( "Cannot find the source image")}
    if(!([System.IO.Path]::IsPathRooted($imageSource))){throw("please enter a full path for your source path")}
    if(!([System.IO.Path]::IsPathRooted($imageTarget))){throw("please enter a full path for your target path")}
    if ($quality -lt 0 -or $quality -gt 100){throw( "quality must be between 0 and 100.")}
 
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    $bmp = [System.Drawing.Image]::FromFile($imageSource)
 
    #hardcoded max canvas size...
    $canvasTargetSize = 3000.0

    if(($bmp.Width) -le $canvasTargetSize) {if(($bmp.Height) -le $canvasTargetSize) {return $True}}
 
    #Encoder parameter for image quality
    $myEncoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($myEncoder, $quality)
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
    return $False
}


    $iteration = 0
    $filelist | Foreach-Object{
        $iteration++
        #Write-Host "resizing image " $iteration " of " $filelist.Count
        $backupName = ($_.DirectoryName + "\original\" + $_.Name)
        if((Test-Path($backupName)) -eq $False ) {
            Copy-Item $_.FullName $backupName
        }
        #We generate a quick and dirty hash to avoid name collisions in case there is already an image named "$file_resized"
        $hash = (Get-Random -minimum 100000 -maximum 999999)
        $newName = $_.FullName.Substring(0, $_.FullName.Length - 4) + "_resized_" + $hash + ".jpg"
        $originalName = $_.FullName
        $er = MakePreviewImages $_.FullName $newName 100
        if($er -eq $False)
        {
           #We wrap it in a while loop because it might fail the first time if the OS locked the file and we want it to succeed always

           while(Test-Path($originalName))
           {
                Remove-Item $originalName
           }
           while((Test-Path($originalName)) -eq $False)
           {
                Rename-Item $newName $originalName
           }
        
        }
        else
        {
           Write-Host ("Skipped " + $_.Name + " because it was small enough")
        }
    }
}

##ACTUAL ENTRY POINT##

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

$filelist = Get-ChildItem ($inputfolder + '\*') -Include *.jpg, *.jpeg
if($filelist -eq $null) {
    Write-Host "ERROR: No images found in directory"
    Return
}

if($filelist -isnot [array])
{
    Write-Host "Single File Selected: $filelist"
    Start-Job $ScriptBlock -arg $filelist | Out-Null
}
else
{
    $totalNumberofImages = $filelist.Length
    $numberOfBuckets = 6
    $numberOfBuckets = [Math]::Min($numberOfBuckets, ($totalNumberofImages))
    $baseamount = [Math]::Floor(($totalNumberofImages/$numberOfBuckets))
    $a = New-Object System.Collections.ArrayList
    if($baseamount -eq 1) 
    {
        $a.Add($filelist[0]) > $null
    }
    else 
    {
        $a.Add($filelist[0..$baseamount]) > $null
    }
    for($i = 1; (($i) -lt $numberOfBuckets); $i++)
    {
        if($baseamount -eq 1) 
        {
            if($i -eq ($numberOfBuckets-1))
            {
                $a.Add($filelist[$i..($totalNumberofImages-1)]) > $null
            }
            else
            {
                $a.Add($filelist[$i]) > $null
            }
            
        }
        else
        {
            $start = ($i * $baseamount) + 1 
            $end = $start + $baseamount
            if(($i) -eq ($numberOfBuckets-1))
            {
                $end = $totalNumberofImages-1
            }
            $a.Add($filelist[$start..$end]) > $null
        }

    }


    $progress = 0
    $imagesResized = 0
    Write-Progress  -Activity "Preparing to Resize" -Status "Preparing to Resize" -CurrentOperation ("Resized $imagesResized of $totalNumberofImages Images")  -PercentComplete $progress

    ForEach ($List in $a)
    {
        Start-Job $ScriptBlock -arg (,$List) | Out-Null
    }

}





# Wait for all to complete
While (Get-Job -State "Running") {
    $imagesResized = $(Get-ChildItem $originalFolder).Count
    $progress = (($imagesResized / $totalNumberOfImages) * 100)
    $progress = [math]::Min($progress, 100)
    if (($progress) -eq 0)
    {
        Write-Progress  -Activity "Preparing to Resize" `
        -Status "Preparing to Resize" `
        -CurrentOperation ("Resized $imagesResized of $totalNumberOfImages Images")  `
        -PercentComplete $progress
    }
    else
    {
        Write-Progress  -Activity "Resizing Images" `
         -Status "Using $($(Get-Job -State Running).count) threads" `
         -CurrentOperation ("Resized $imagesResized of $totalNumberOfImages Images")  `
         -PercentComplete $progress
    }
    Start-Sleep -Milliseconds 33
   # Get-Job | Receive-Job 
}


Remove-Job *

Write-Output "Done processing! Elapsed Time: $($elapsed.Elapsed.ToString())"
