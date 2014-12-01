#!/bin/sh

accversion=0.999
accsparkle=2.13.$accversion
sparkleroot=/Users/smk/Accession/sparkle
accessionroot=/Users/smk/Accession/AccessionDesktop

function pause(){
   read -p "Press [Enter] key to $* or CTRL+C to quit..."
}

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Not running as root"
    exit
fi

echo
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo sparkleroot = $sparkleroot
echo accessionroot = $accessionroot
echo Accession dmg version label = $accversion 
echo Version for sparkle = $accsparkle
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
pause 'confirm that the above values are correct'
#pause 'build a new Sparkle framework containing your changes'
cd $sparkleroot; xcodebuild 
#pause 'copy the new Sparkle framework to the system framework library'
rm -R /System/Library/Frameworks/Sparkle.framework; sudo cp -R build/Release/Sparkle.framework /System/Library/Frameworks 
#pause 'compile the JNI using the modified framework'
cd $accessionroot/jitsi/src/native/macosx/sparkle; make clean; make; make install 
#pause 'copy the new Sparkle framework to the the Accession Desktop Mac installer directory'
cd $accessionroot/jitsi/resources/install/macosx; cp -R $sparkleroot/build/Release/Sparkle.framework .
#pause 'remove all aliases from the copy of Sparkle.framework in the Accession Desktop Mac installer directory'
find ./Sparkle.framework/ -type l -exec rm -f {} \;  
#pause 'zip up Sparkle.framework and remove the non-zipped Sparkle.framework folder'
rm Sparkle.framework.zip; zip -r -m Sparkle.framework.zip Sparkle.framework 
pause 'build a dmg to test - EJECT ACCESSION FIRST'
cd $accessionroot; ant cc-build-macosx -Dlabel=$accversion -Dsparkle=$accsparkle

