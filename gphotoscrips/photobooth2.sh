#!/bin/bash

# --- 1. CONFIGURATION ---
SAVE_PATH="/home/$USER/Pictures/Photobooth"
mkdir -p "$SAVE_PATH"

# --- 2. FUNCTIONS ---

# Function to stop everything and release the camera
stop_preview() {
    echo "Stopping live preview and releasing USB..."
    # Kill gphoto2 and ffmpeg
    pkill -INT -f gphoto2 2>/dev/null
    #pkill -9 ffmpeg 2>/dev/null
    # Kill the desktop's auto-mount monitor (Critical for Trixie)
    #pkill -9 gvfsd-gphoto2 2>/dev/null
    
    # Wait for the Linux kernel to clear the USB lock
    sleep 2
}

# Function to start the live preview bridge
start_preview() {
    echo "Starting live preview on /dev/video0..."
    # Load the virtual camera driver
    sudo modprobe v4l2loopback exclusive_caps=1 card_label="GPhoto2-Webcam" 2>/dev/null
    gphoto2 --set-config /main/imgsettings/iso=3200    
    # Bridge gphoto2 to ffmpeg
    # forced MJPEG input and explicit scale range to fix Trixie warnings
    gphoto2 --stdout --capture-movie | ffmpeg -loglevel error -f mjpeg -i - \
        -vf "scale=in_range=pc:out_range=pc,format=yuv420p" \
        -vcodec rawvideo -pix_fmt yuv420p -color_range 2 -f v4l2 /dev/video0 &
}

# Function triggered by the SIGUSR1 signal
capture_image() {
    echo "Capture signal received!"
    stop_preview
    gphoto2 --set-config /main/imgsettings/iso=400
    # Check if a custom filename was sent via /tmp
    if [ -f /tmp/next_filename ]; then
        CUSTOM_NAME=$(cat /tmp/next_filename)
        FILENAME="${CUSTOM_NAME}"
        sudo rm /tmp/next_filename
    else
        FILENAME="photo_$(date +%Y%m%d_%H%M%S).jpg"
    fi
    
    echo "Capturing high-resolution photo: $FILENAME"
    # Ensure Lens is on Manual Focus or this command might hang!
    gphoto2 --set-config /main/actions/autofocusdrive=1 --capture-image-and-download --filename "$FILENAME" \
    --no-keep \
    --set-config capturetarget=1 \
    --force-overwrite
    sudo chown www-data:www-data $FILENAME    
    sudo chmod 775 $FILENAME
    echo "Photo saved. Restarting preview..."
    start_preview
}

# --- 3. THE TRAP ---
# This tells the script to run capture_image when it receives SIGUSR1
trap 'capture_image' SIGUSR1

# --- 4. MAIN EXECUTION ---

# Clean up any old ghost processes before starting
stop_preview

# Start the first preview
start_preview

echo "====================================================="
echo " Photobooth Script Active (PID: $$)"
echo " Save Path: $SAVE_PATH"
echo " Trigger: pkill -USR1 -f photobooth.sh"
echo "====================================================="

# MANDATORY LOOP FOR TRIXIE: 
# Using 'wait' allows the script to remain responsive to signals.
while true; do
    sleep 1 & wait $!
done
