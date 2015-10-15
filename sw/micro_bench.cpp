// ***************************************************************************
//
//        UCLA CDSC Microbenchmark Software
//
// Engineer:            Peng Wei
// Create Date:         Oct 13, 2015
// ***************************************************************************

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif // HAVE_CONFIG_H

#ifdef STDC_HEADERS
# include <stdlib.h>
# include <stddef.h>
#else
# ifdef HAVE_STDLIB_H
#    include <stdlib.h>
# else
#    error Required system header stdlib.h not found.
# endif // HAVE_STDLIB_H
#endif // STDC_HEADERS

#ifdef HAVE_STRING_H
# include <string.h>
#endif // HAVE_STRING_H

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif // HAVE_UNISTD_H

#include <iostream>
#include <iomanip>
#include <algorithm>

#include "micro_bench.h"
#include "my_timer.h"

#include <aalsdk/ccilib/CCILib.h>
#include <aalsdk/aalclp/aalclp.h>

USING_NAMESPACE(std)
USING_NAMESPACE(AAL)
USING_NAMESPACE(CCILib)

///////////////////////////////////////////////
BEGIN_C_DECLS

struct CCIDemoCmdLine
{
    btUIntPtr               flags;
#define CCIDEMO_CMD_FLAG_HELP       0x00000001
#define CCIDEMO_CMD_FLAG_VERSION    0x00000002

    CCIDeviceImplementation target;
    int                     log;
    int                     trace;
};

struct CCIDemoCmdLine gCCIDemoCmdLine = 
{
    0,
    CCI_NULL,
    0,
    0
};

int ccidemo_on_nix_long_option_only(AALCLP_USER_DEFINED , const char * );
int ccidemo_on_nix_long_option(AALCLP_USER_DEFINED , const char * , const char * );

aalclp_option_only ccidemo_nix_long_option_only = { ccidemo_on_nix_long_option_only, };
aalclp_option      ccidemo_nix_long_option      = { ccidemo_on_nix_long_option,      };

void help_msg_callback(FILE * , struct _aalclp_gcs_compliance_data * );
void showhelp(FILE * , struct _aalclp_gcs_compliance_data * );

AALCLP_DECLARE_GCS_COMPLIANT(stdout,
                             "CCIDemo",
                             CCILIB_VERSION,
                             "",
                             help_msg_callback,
                             &gCCIDemoCmdLine)

int parsecmds(struct CCIDemoCmdLine * , int , char *[] );
int verifycmds(struct CCIDemoCmdLine * );

END_C_DECLS
///////////////////////////////////////////////

int main(int argc, char *argv[])
{
    if (argc < 2) {
        showhelp(stdout, &_aalclp_gcs_data);
        return 1;
    } else if (parsecmds(&gCCIDemoCmdLine, argc, argv)) {
        cerr << "Error scanning command line." << endl;
        return 2;
    } else if (flag_is_set(gCCIDemoCmdLine.flags, CCIDEMO_CMD_FLAG_HELP | CCIDEMO_CMD_FLAG_VERSION)) {
        return 0;
    } else if (verifycmds(&gCCIDemoCmdLine)) {
        return 3;
    }
    int nDataSize = 1 << atoi(argv[2]);
    int nLoopNum  = atoi(argv[3]);

    // 0th: initialize the timer at the beginning of the program
    timespec timer = tic();

    const CCIDeviceImplementation CCIDevImpl = gCCIDemoCmdLine.target;

    ICCIDeviceFactory *pCCIDevFactory = GetCCIDeviceFactory(CCIDevImpl);

    ICCIDevice *pCCIDevice = pCCIDevFactory->CreateCCIDevice();

#if (1 == ENABLE_DEBUG)
    pCCIDevice->GetSynchronizer()->SetLogLevel(gCCIDemoCmdLine.log);
    pCCIDevice->GetSynchronizer()->SetTraceLevel(gCCIDemoCmdLine.trace);
#endif // ENABLE_DEBUG

    const int INPUT_BUFFER_SIZE = sizeof(int) * nDataSize;
    const int OUTPUT_BUFFER_SIZE = CL(1); // results are reduced to only one integer
    ICCIWorkspace *pDSMWorkspace    = pCCIDevice->AllocateWorkspace(DSM_SIZE);
    ICCIWorkspace *pInputWorkspace  = pCCIDevice->AllocateWorkspace(INPUT_BUFFER_SIZE);
    ICCIWorkspace *pOutputWorkspace = pCCIDevice->AllocateWorkspace(OUTPUT_BUFFER_SIZE);

    volatile btVirtAddr pInputUsrVirt  = pInputWorkspace->GetUserVirtualAddress(); 
    volatile btVirtAddr pOutputUsrVirt = pOutputWorkspace->GetUserVirtualAddress();
    volatile btVirtAddr pDSMUsrVirt    = pDSMWorkspace->GetUserVirtualAddress();
    volatile btVirtAddr pDSMStatusVirt = pDSMWorkspace->GetUserVirtualAddress() + DSM_STATUS_COMPLETE;

    // memset((void *)pOutputUsrVirt, 0, pOutputWorkspace->GetSizeInBytes());
    memset((void *)pDSMUsrVirt, 0, pDSMWorkspace->GetSizeInBytes());

    bt32bitCSR csr;

    // Assert CAFU Reset
    csr = 0;
    pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
    csr |= 0x01000000;
    pCCIDevice->SetCSR(CSR_CIPUCTL, csr);

    // De-assert CAFU Reset
    csr = 0;
    pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
    csr &= ~0x01000000;
    pCCIDevice->SetCSR(CSR_CIPUCTL, csr);

    // Set DSM base, high then low
    pCCIDevice->SetCSR(CSR_AFU_DSM_BASEH, pDSMWorkspace->GetPhysicalAddress() >> 32);
    pCCIDevice->SetCSR(CSR_AFU_DSM_BASEL, pDSMWorkspace->GetPhysicalAddress() & 0xffffffff);

    // Poll for AFU ID
    do
    {
        csr = *(volatile btUnsigned32bitInt *)pDSMUsrVirt;
    } while( 0 == csr );

    // Print the AFU ID
    cout << "[Start] AFU ID=";
    for ( int i = 0 ; i < 4 ; ++i ) {
        cout << std::setw(8) << std::hex << std::setfill('0')
            << *(btUnsigned32bitInt *)(pDSMUsrVirt + (3 - i) * sizeof(btUnsigned32bitInt));
    }
    cout << endl;

    // Assert Device Reset
    // Currently unnecessary

    // Clear the DSM
    // memset((void *)pDSMUsrVirt, 0, pDSMWorkspace->GetSizeInBytes());

    // De-assert Device Reset
    // Currently unnecessary

    // Set input workspace address
    pCCIDevice->SetCSR(CSR_SRC_ADDR, CACHELINE_ALIGNED_ADDR(pInputWorkspace->GetPhysicalAddress()));

    // Set output workspace address
    pCCIDevice->SetCSR(CSR_DST_ADDR, CACHELINE_ALIGNED_ADDR(pOutputWorkspace->GetPhysicalAddress()));

    // Set I/O data size
    pCCIDevice->SetCSR(CSR_DATA_SIZE, CACHELINE_ALIGNED_ADDR(nDataSize * sizeof(int)));

    // Set loop number
    pCCIDevice->SetCSR(CSR_LOOP_NUM, nLoopNum);

    // 1st: setup time of the one-time preprocess
    toc(&timer, "one-time preprocess");

    // Initialize input workspace
    for (int i=0; i < nDataSize; i++)
      *((volatile btUnsigned32bitInt *)pInputUsrVirt + i) = 2*(i%16)+1; 

    // Set the test mode
    // TO BE SUPPORTED

    // 2nd: initialization time (ignored)
    timer = tic();

    // Start the test
    pCCIDevice->SetCSR(CSR_CTL, 0x2);

    // Poll for AFU ID
    do
    {
        csr = *(volatile btUnsigned32bitInt *)pDSMStatusVirt;
    } while( 0 == csr );

    csr = *(volatile btUnsigned32bitInt *)pOutputUsrVirt;
    cout << "[Complete] final_result = " << csr << endl;

    // 3rd: kernel execution time (including data transferring)
    toc(&timer, "kernel execution");
    
    // Stop the device
    // TO BE SUPPORTED

    // Release the Workspaces
    pCCIDevice->FreeWorkspace(pInputWorkspace);
    pCCIDevice->FreeWorkspace(pOutputWorkspace);
    pCCIDevice->FreeWorkspace(pDSMWorkspace);

    // Release the CCI Device instance.
    pCCIDevFactory->DestroyCCIDevice(pCCIDevice);

    // Release the CCI Device Factory instance.
    delete pCCIDevFactory;
  
    // 4th: one-time postprocess time
    toc(&timer, "one-time postprocess");

    return 0;
}


BEGIN_C_DECLS

int ccidemo_on_nix_long_option_only(AALCLP_USER_DEFINED user, const char *option)
{
   struct CCIDemoCmdLine *cl = (struct CCIDemoCmdLine *)user;

   if ( 0 == strcmp("--help", option) ) {
      flag_setf(cl->flags, CCIDEMO_CMD_FLAG_HELP);
   } else if ( 0 == strcmp("--version", option) ) {
      flag_setf(cl->flags, CCIDEMO_CMD_FLAG_VERSION);
   }

   return 0;
}

int ccidemo_on_nix_long_option(AALCLP_USER_DEFINED user, const char *option, const char *value)
{
   struct CCIDemoCmdLine *cl = (struct CCIDemoCmdLine *)user;

   if ( 0 == strcmp("--target", option) ) {
      if ( 0 == strcasecmp("aal", value) ) {
#if (1 == CCILIB_ENABLE_AAL)
         cl->target = CCI_AAL;
#else
         cout << "The version of CCILib was built without support for --target=AAL" << endl;
         return 1;
#endif // CCILIB_ENABLE_AAL
      } else if ( 0 == strcasecmp("ase", value) ) {
#if (1 == CCILIB_ENABLE_ASE)
         cl->target = CCI_ASE;
#else
         cout << "The version of CCILib was built without support for --target=ASE" << endl;
         return 2;
#endif // CCILIB_ENABLE_ASE
      } else if ( 0 == strcasecmp("direct", value) ) {
#if (1 == CCILIB_ENABLE_DIRECT)
         cl->target = CCI_DIRECT;
#else
         cout << "The version of CCILib was built without support for --target=Direct" << endl;
         return 3;
#endif // CCILIB_ENABLE_DIRECT
      } else {
         cout << "Invalid value for --target : " << value << endl;
         return 4;
      }
   } else if ( 0 == strcmp("--log", option) ) {
      char *endptr = NULL;

      cl->log = (int)strtol(value, &endptr, 0);
      if ( endptr != value + strlen(value) ) {
         cl->log = 0;
      } else if ( cl->log < 0) {
         cl->log = 0;
      } else if ( cl->log > 7) {
         cl->log = 7;
      }
   } else if ( 0 == strcmp("--trace", option) ) {
      char *endptr = NULL;

      cl->trace = (int)strtol(value, &endptr, 0);
      if ( endptr != value + strlen(value) ) {
         cl->trace = 0;
      } else if ( cl->trace < 0) {
         cl->trace = 0;
      } else if ( cl->trace > 7) {
         cl->trace = 7;
      }
   }

   return 0;
}

void help_msg_callback(FILE *fp, struct _aalclp_gcs_compliance_data *gcs)
{
   fprintf(fp, "Usage:\n");
   fprintf(fp, "   CCIDemo [--target=<TARGET>]\n");
   fprintf(fp, "\n");
   fprintf(fp, "      <TARGET> = one of { ");
#if (1 == CCILIB_ENABLE_AAL)
   fprintf(fp, "AAL ");
#endif // CCILIB_ENABLE_AAL
#if (1 == CCILIB_ENABLE_ASE)
   fprintf(fp, "ASE ");
#endif // CCILIB_ENABLE_ASE
#if (1 == CCILIB_ENABLE_DIRECT)
   fprintf(fp, "Direct ");
#endif // CCILIB_ENABLE_DIRECT
   fprintf(fp, "}\n");
   fprintf(fp, "\n");
}

void showhelp(FILE *fp, struct _aalclp_gcs_compliance_data *gcs)
{
   help_msg_callback(fp, gcs);
}

int parsecmds(struct CCIDemoCmdLine *cl, int argc, char *argv[])
{
   int    res;
   int    clean;
   aalclp clp;

   res = aalclp_init(&clp);
   if ( 0 != res ) {
      cerr << "aalclp_init() failed : " << res << ' ' << strerror(res) << endl;
      return res;
   }

   ccidemo_nix_long_option_only.user = cl;
   aalclp_add_nix_long_option_only(&clp, &ccidemo_nix_long_option_only);

   ccidemo_nix_long_option.user = cl;
   aalclp_add_nix_long_option(&clp, &ccidemo_nix_long_option);

   res = aalclp_add_gcs_compliance(&clp);
   if ( 0 != res ) {
      cerr << "aalclp_add_gcs_compliance() failed : " << res << ' ' << strerror(res) << endl;
      goto CLEANUP;
   }

   res = aalclp_scan_argv(&clp, argc, argv);
   if ( 0 != res ) {
      cerr << "aalclp_scan_argv() failed : " << res << ' ' << strerror(res) << endl;
   }

CLEANUP:
   clean = aalclp_destroy(&clp);
   if ( 0 != clean ) {
      cerr << "aalclp_destroy() failed : " << clean << ' ' << strerror(clean) << endl;
   }

   return res;
}

int verifycmds(struct CCIDemoCmdLine *cl)
{
   if ( CCI_NULL == cl->target ) {
      cout << "No valid --target specified." << endl;
      return 1;
   }

   return 0;
}

END_C_DECLS

