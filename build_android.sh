##git clone https://github.com/Bilibili/ijkplayer.git ijkplayer-android
##cd ijkplayer-android
git checkout -B latest k0.8.4

./init-android.sh

cd android/contrib
./compile-ffmpeg.sh clean
./compile-ffmpeg.sh all

cd ..
./compile-ijk.sh all

