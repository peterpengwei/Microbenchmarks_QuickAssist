TARGET  := micro_bench

SOURCES := 

SOURCE_CPP := micro_bench.cpp
AAL_SRCDIR := /curr/pengwei/QuickAssist/quickassist/aalsdk_splrm-4.1.0/aalsdk_splrm-4.1.0
AAL_BUILDDIR := /curr/pengwei/QuickAssist/quickassist/aalsdk_splrm-4.1.0/aalsdk_splrm-4.1.0/my_build

COBJECTS := $(patsubst %.c, %.o, $(SOURCES))
CCOBJECTS := $(patsubst %.cpp, %.o, $(SOURCE_CPP))
LIBPATH := .

AAL_INC=\
-I$(AAL_SRCDIR)/include \
-I$(AAL_BUILDDIR)

AAL_LDADD=\
$(AAL_BUILDDIR)/aas/OSAL/libOSAL.la \
$(AAL_BUILDDIR)/aas/AASLib/libAAS.la \
$(AAL_BUILDDIR)/CCILib/libCCI.la \
$(AAL_BUILDDIR)/clp/libaalclp.la

CXX = gcc
CXXFLAGS    = -g -Wall -Wno-unused-function -O2 $(AAL_INC)
HAVE_CONFIG = -DHAVE_CONFIG_H
LDFLAGS     = $(HAVE_CONFIG) -lm -lstdc++

all: $(TARGET)

$(TARGET): $(COBJECTS) $(CCOBJECTS)
	libtool --mode=link g++ *.o -o $(TARGET) $(LDFLAGS) $(AAL_LDADD)

$(COBJECTS): %.o: %.c
	$(CXX) -c $(CXXFLAGS) -o $@ $<

$(CCOBJECTS): %.o: %.cpp
	gcc -c -x c++ $(CXXFLAGS) $(HAVE_CONFIG) -o $@ $<

clean:
	rm -rf *.o $(TARGET) .libs/
