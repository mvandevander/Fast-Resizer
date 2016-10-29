# Fast-Resizer
A reasonably fast job-threaded jpeg resizer script for PowerShell.

## What it does

It takes a folder full of jpeg images, resizes them to where they have a dimension of 3000 pixels on the longest side, keeping the original aspect ratio. It also backs up the original image to a subfolder called "original"

## (REQUIRES AT LEAST POWERSHELL VERSION 4.0)

## Instructions

Simply run the powershell script, and use the pop-up window to select a folder full of images you want resized. If you have issues, or want to deploy on multiple computers, I recommend using the included batch file (preferably through a shortcut icon), as the batch file will let you run a powershell script without any end user scaring pop-ups asking about changing the security permissions.

## Thanks

Please note that this script is cobbled together with help from various sources around the internet. It's sort of one of those hacky Stack Overflow copy-pasta type scripts. But it works well enough. 

I would like particularly to give credit to the following sources:

Custom (Windows Vista+) style Folder Browser came from:
https://www.sapien.com/forums/viewtopic.php?t=8662 via http://www.lyquidity.com/devblog/?p=136

Original image resizing code came from Benoit Patra:
http://benoitpatra.com/2014/09/14/resize-image-and-preserve-ratio-with-powershell/
