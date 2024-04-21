#!/bin/bash

#Format your partitions / and /boot then mount your root at /mnt/lfs and boot at /mnt/lfs/boot
#then run this script

export LFS=/mnt/lfs

echo $LFS

mkdir -v $LFS/sources

chmod -v a+wt $LFS/sources

cp -v * $LFS/sources

pushd $LFS/sources
  md5sum -c md5sums
popd

cd $LFS/sources

pwd

echo "MD5SUM check complete. continue? (y/n)"
read -n 1 user_input

if [ "$user_input" != "y" ]; then
    echo "Exiting."
    exit 1
fi
echo "The script now continues"

#4.2 Creating a limited directory layout

mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}

for i in bin lib sbin; do
  ln -sv usr/$i $LFS/$i
done

case $(uname -m) in
  x86_64) mkdir -pv $LFS/lib64 ;;
esac

mkdir -pv $LFS/tools

# 4.3 Adding the LFS user

groupadd lfs

useradd -s /bin/bash -g lfs -m -k /dev/null lfs

passwd lfs

chown -v lfs $LFS/{usr{,/*},lib,var,etc,bin,sbin,tools}
case $(uname -m) in
  x86_64) chown -v lfs $LFS/lib64 ;;
esac

su - lfs

cat > ~/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

cat > ~/.bashrc << "EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
export MAKEFLAGS=-j8
EOF

source ~/.bash_profile

echo $LFS

echo "Users and bashrc is configured, continue with compiling? (y/n)"
read -n 1 user_input

if [ "$user_input" != "y" ]; then
    echo "Exiting."
    exit 1
fi
echo "The script now continues"
#-------------------------------------------------------------------------------------
# 5.2. Binutils-2.42 - Pass 1
tar xvf /mnt/lfs/sources/binutils-2.42.tar.xz
cd /mnt/lfs/sources/binutils-2.42
mkdir -v build
cd build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT   \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-default-hash-style=gnu
make
make install
rm -rfv /mnt/lfs/sources/binutils-2.42
#-------------------------------------------------------------------------------------
# 5.3. GCC-13.2.0 - Pass 1
#-------------------------------------------------------------------------------------
tar xvf /mnt/lfs/sources/gcc-13.2.0.tar.xz
cd /mnt/lfs/sources/gcc-13.2.0
tar -xf ../mpfr-4.2.1.tar.xz
mv -v mpfr-4.2.1 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac
mkdir -v build
cd       build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.39 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make
make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/gcc-13.2.0
#-------------------------------------------------------------------------------------
# Linux-6.7.4 API Headers
#-------------------------------------------------------------------------------------

tar xvf /mnt/lfs/sources/linux-6.7.4.tar.xz
cd /mnt/lfs/sources/linux-6.7.4
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/linux-6.7.4
#-------------------------------------------------------------------------------------
# 5.5. Glibc-2.39
#-------------------------------------------------------------------------------------
tar xvf /mnt/lfs/sources/glibc-2.39.tar.xz
cd /mnt/lfs/sources/glibc-2.39
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
            ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
    ;;
esac
patch -Np1 -i ../glibc-2.39-fhs-1.patch
mkdir -v build
cd       build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=4.19               \
      --with-headers=$LFS/usr/include    \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib
make
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
cd /mnt/lfs/sources/
rm -rfv /mnt/lfs/sources/glibc-2.39

#-------------------------------------------------------------------------------------
# 5.6. Libstdc++ from GCC-13.2.0
#-------------------------------------------------------------------------------------

tar xvf /mnt/lfs/sources/gcc-13.2.0.tar.xz
cd /mnt/lfs/sources/gcc-13.2.0
mkdir -v build
cd       build
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --build=$(../config.guess)      \
    --prefix=/usr                   \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/13.2.0
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/gcc-13.2.0

#-------------------------------------------------------------------------------------
# M4-1.4.19
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/m4-1.4.19.tar.xz
cd /mnt/lfs/sources/m4-1.4.19

./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/m4-1.4.19

#-------------------------------------------------------------------------------------
# Ncurses-6.4-20230520
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/ncurses-6.4-20230520.tar.xz
cd /mnt/lfs/sources/ncurses-6.4-20230520
sed -i s/mawk// configure
mkdir build
pushd build
  ../configure
  make -C include
  make -C progs tic
popd
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping          \
            --enable-widec
make
make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i $LFS/usr/include/curses.h
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/ncurses-6.4-20230520

#-------------------------------------------------------------------------------------
# 6.4. Bash-5.2.21
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/bash-5.2.21.tar.gz
cd /mnt/lfs/sources/bash-5.2.21

./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/bash-5.2.21

#-------------------------------------------------------------------------------------
# 6.5. Coreutils-9.4
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/coreutils-9.4.tar.xz
cd /mnt/lfs/sources/coreutils-9.4
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8

cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/coreutils-9.4

#-------------------------------------------------------------------------------------
# 6.6. Diffutils-3.10
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/diffutils-3.10.tar.xz
cd /mnt/lfs/sources/diffutils-3.10
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/diffutils-3.10

#-------------------------------------------------------------------------------------
# 6.7. File-5.45
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/file-5.45.tar.gz
cd /mnt/lfs/sources/file-5.45
mkdir build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/file-5.45

#-------------------------------------------------------------------------------------
# 6.8. Findutils-4.9.0
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/findutils-4.9.0.tar.xz
cd /mnt/lfs/sources/findutils-4.9.0

./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/findutils-4.9.0

#-------------------------------------------------------------------------------------
# 6.9. Gawk-5.3.0
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/gawk-5.3.0.tar.xz
cd /mnt/lfs/sources/gawk-5.3.0
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/gawk-5.3.0

#-------------------------------------------------------------------------------------
# 6.10. Grep-3.11
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/grep-3.11.tar.xz
cd /mnt/lfs/sources/grep-3.11
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install

cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/grep-3.11

#-------------------------------------------------------------------------------------
# 6.11. Gzip-1.13
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/gzip-1.13.tar.xz
cd /mnt/lfs/sources/gzip-1.13
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install

cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/gzip-1.13

#-------------------------------------------------------------------------------------
# 6.12. Make-4.4.1
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/make-4.4.1.tar.gz
cd /mnt/lfs/sources/make-4.4.1
./configure --prefix=/usr   \
            --without-guile \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install

cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/make-4.4.1

#-------------------------------------------------------------------------------------
# 6.13. Patch-2.7.6
#-------------------------------------------------------------------------------------

cd /mnt/lfs/sources
tar xvf /mnt/lfs/sources/patch-2.7.6.tar.xz
cd /mnt/lfs/sources/patch-2.7.6
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/patch-2.7.6

#-------------------------------------------------------------------------------------
# 6.14. Sed-4.9
#-------------------------------------------------------------------------------------

tar xvf /mnt/lfs/sources/sed-4.9.tar.xz
cd /mnt/lfs/sources/sed-4.9
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/sed-4.9

#-------------------------------------------------------------------------------------
# 6.15. Tar-1.35
#-------------------------------------------------------------------------------------

tar xvf /mnt/lfs/sources/tar-1.35.tar.xz
cd /mnt/lfs/sources/tar-1.35
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install

cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/tar-1.35

#-------------------------------------------------------------------------------------
# 6.16. Xz-5.4.6
#-------------------------------------------------------------------------------------

tar xvf /mnt/lfs/sources/xz-5.4.6.tar.xz
cd /mnt/lfs/sources/xz-5.4.6
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.4.6
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/xz-5.4.6

#-------------------------------------------------------------------------------------
# 6.17. Binutils-2.42 - Pass 2
#-------------------------------------------------------------------------------------

tar xvf /mnt/lfs/sources/binutils-2.42.tar.xz
cd /mnt/lfs/sources/binutils-2.42
sed '6009s/$add_dir//' -i ltmain.sh
mkdir -v build
cd       build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
cd /mnt/lfs/sources
rm -rfv /mnt/lfs/sources/binutils-2.42

#-------------------------------------------------------------------------------------
# 6.17. Binutils-2.42 - Pass 2
#-------------------------------------------------------------------------------------

tar xvf /mnt/lfs/sources/gcc-13.2.0.tar.xz
cd /mnt/lfs/sources/gcc-13.2.0
tar -xf ../mpfr-4.2.1.tar.xz
mv -v mpfr-4.2.1 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir -v build
cd       build
../configure                                       \
    --build=$(../config.guess)                     \
    --host=$LFS_TGT                                \
    --target=$LFS_TGT                              \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc      \
    --prefix=/usr                                  \
    --with-build-sysroot=$LFS                      \
    --enable-default-pie                           \
    --enable-default-ssp                           \
    --disable-nls                                  \
    --disable-multilib                             \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libquadmath                          \
    --disable-libsanitizer                         \
    --disable-libssp                               \
    --disable-libvtv                               \
    --enable-languages=c,c++
make
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc

#-------------------------------------------------------------------------------------
# Chapter 7. Entering Chroot and Building Additional Temporary Tools
#-------------------------------------------------------------------------------------

chown -R root:root $LFS/{usr,lib,var,etc,bin,sbin,tools}
case $(uname -m) in
  x86_64) chown -R root:root $LFS/lib64 ;;
esac
mkdir -pv $LFS/{dev,proc,sys,run}
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run


if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login
