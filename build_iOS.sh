##git clone https://github.com/Bilibili/ijkplayer.git ijkplayer-ios
##cd ijkplayer-ios
##git checkout -B latest k0.8.4

./init-ios-openssl.sh

cd ios
./compile-ffmpeg.sh clean
./compile-ffmpeg.sh all

