BASEDIR= $(shell cd ../../../; pwd)

OS := $(shell uname)
HOSTCPU= $(shell ${BASEDIR}/forth/lib/hostcpu.sh)
HOSTDIR= ${BASEDIR}/cpu/${HOSTCPU}/${OS}
BUILDSH= ${BASEDIR}/forth/lib/build.sh

all: basefw.dic

.PHONY: FORCE all clean

.PRECIOUS: builder.dic

${HOSTDIR}/forth: FORCE
	@gmake -C ${HOSTDIR} forth

${HOSTDIR}/armforth: FORCE
	@gmake -C ${HOSTDIR} armforth

build: ${HOSTDIR}/forth ${HOSTDIR}/armforth
	@ln -sf ${BUILDSH} build

%.dic: FORCE build
	./build $@

builder.dic: FORCE build
	-[ ! -f builder.sav ] && cp builder.dic builder.sav
	./build builder.dic

inflate.bin:
	gmake -C ../${OS} ../build/inflate.bin

# Don't use *.dic so as not to remove builder.dic
clean:
	rm -f tools.dic kernel.dic basefw.dic
	rm -f *.tag *.log headers *~ inflate.bin build
	@gmake -C ../${OS} clean
	@gmake -C ${HOSTDIR} clean
