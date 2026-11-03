// SPDX-License-Identifier: MIT
// Minimal client for Microsoft's documented IDxcAssembler / IDxcValidator interfaces (Windows + Linux).
// usage: dxc_assemble <dxcompiler.dll|libdxcompiler.so> assemble|validate IN OUT
// Build-only tool: no Vulkan, Wine, or GPU execution.
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
#include <cwchar>
#ifdef _WIN32
#include <windows.h>
#define dlopen(p,f) ((void*)LoadLibraryA(p))
#define dlsym(l,n) ((void*)GetProcAddress((HMODULE)(l),n))
static const char* dlerror(){return "LoadLibrary failed (put dxcompiler.dll and dxil.dll next to it)";}
#else
#include <dlfcn.h>
#endif
struct Guid { uint32_t a; uint16_t b,c; uint8_t d[8]; };
using HR=int32_t;
struct DxUnknown {
    virtual HR QueryInterface(const Guid&,void**)=0;
    virtual uint32_t AddRef()=0;
    virtual uint32_t Release()=0;
};
struct DxBlob : DxUnknown { virtual void* GetBufferPointer()=0; virtual size_t GetBufferSize()=0; };
struct DxEncoding : DxBlob { virtual HR GetEncoding(int*,uint32_t*)=0; };
struct DxResult : DxUnknown {
    virtual HR GetStatus(HR*)=0;
    virtual HR GetResult(DxBlob**)=0;
    virtual HR GetErrorBuffer(DxEncoding**)=0;
};
struct Assembler : DxUnknown { virtual HR AssembleToContainer(DxBlob*,DxResult**)=0; };
struct Validator : DxUnknown { virtual HR Validate(DxBlob*,uint32_t,DxResult**)=0; };
struct OptPass : DxUnknown {
    virtual HR GetOptionName(wchar_t**)=0; virtual HR GetDescription(wchar_t**)=0; virtual HR GetOptionArgCount(uint32_t*)=0;
    virtual HR GetOptionArgName(uint32_t,wchar_t**)=0; virtual HR GetOptionArgDescription(uint32_t,wchar_t**)=0;
};
struct Optimizer : DxUnknown {
    virtual HR GetAvailablePassCount(uint32_t*)=0; virtual HR GetAvailablePass(uint32_t,OptPass**)=0;
    virtual HR RunOptimizer(DxBlob*,const wchar_t**,uint32_t,DxBlob**,DxEncoding**)=0;
};
struct DxInput final : DxBlob {
    std::string bytes;
    explicit DxInput(const char* path) { std::ifstream f(path,std::ios::binary); bytes.assign(std::istreambuf_iterator<char>(f),{}); }
    HR QueryInterface(const Guid&,void** p) override {*p=nullptr; return HR(0x80004002);}
    uint32_t AddRef() override {return 1;}
    uint32_t Release() override {return 1;}
    void* GetBufferPointer() override {return bytes.data();}
    size_t GetBufferSize() override {return bytes.size();}
};
// messages: to stderr, or (batch) into the job's answer
static std::string* g_msg=nullptr;
static void say(const void* p,size_t n) { if(g_msg) g_msg->append(static_cast<const char*>(p),n); else std::fwrite(p,1,n,stderr); }
static void sayf(const char* fmt,unsigned v) { char b[128]; int n=std::snprintf(b,sizeof b,fmt,v); if(n>0) say(b,(size_t)n); }
static DxBlob* output(DxResult* result) {
    if (!result) return nullptr;
    DxEncoding* errors=nullptr; result->GetErrorBuffer(&errors);
    if (errors) {say(errors->GetBufferPointer(),errors->GetBufferSize()); errors->Release();}
    HR status=-1; result->GetStatus(&status);
    if (status<0) {sayf("DXC status 0x%x\n",unsigned(status)); return nullptr;}
    DxBlob* blob=nullptr; result->GetResult(&blob); return blob;
}
#ifdef _WIN32
// batch (Windows): one process for many jobs, so a build under Wine starts dxc.exe / this tool once per worker instead
// of once per call. Each stdin line is a job, its words separated by tabs:
//   dxc ARGS...                     as dxc.exe ARGS (a compile with -Fo / -Fc, or -dumpbin IN -Fc OUT), through the
//                                   same IDxcCompiler3 calls dxc.exe makes
//   assemble IN OUT | validate IN OUT | opt IN OUT PASS...   as the commands below
// Each job answers one line: "RC <exit code>\t<messages, newlines as \x1f>".
struct DxcBuffer { const void* Ptr; size_t Size; uint32_t Encoding; };
struct DxBlobUtf16 : DxBlob { virtual const wchar_t* GetStringPointer()=0; virtual size_t GetStringLength()=0; };
struct DxResult2 : DxResult {
    virtual int HasOutput(int)=0;
    virtual HR GetOutput(int,const Guid&,void**,DxBlobUtf16**)=0;
};
struct IncludeHandler : DxUnknown {};
struct Utils : DxUnknown {
    virtual HR CreateBlobFromBlob(DxBlob*,uint32_t,uint32_t,DxBlob**)=0;
    virtual HR CreateBlobFromPinned(const void*,uint32_t,uint32_t,DxEncoding**)=0;
    virtual HR MoveToBlob(const void*,void*,uint32_t,uint32_t,DxEncoding**)=0;
    virtual HR CreateBlob(const void*,uint32_t,uint32_t,DxEncoding**)=0;
    virtual HR LoadFile(const wchar_t*,uint32_t*,DxEncoding**)=0;
    virtual HR CreateReadOnlyStreamFromBlob(DxBlob*,void**)=0;
    virtual HR CreateDefaultIncludeHandler(IncludeHandler**)=0;
};
struct Compiler3 : DxUnknown {
    virtual HR Compile(const DxcBuffer*,const wchar_t**,uint32_t,IncludeHandler*,const Guid&,void**)=0;
    virtual HR Disassemble(const DxcBuffer*,const Guid&,void**)=0;
};
static const Guid kResultIid={0x58346cda,0xdde7,0x4497,{0x94,0x61,0x6f,0x87,0xaf,0x5e,0x06,0x59}};
static const Guid kBlobIid={0x8ba5fb08,0x5195,0x40e2,{0xac,0x58,0x0d,0x98,0x9c,0x3a,0x01,0x02}};
enum { kOutObject=1, kOutErrors=2, kOutDisassembly=5 };

static std::wstring widen(const std::string& s) {
    int n=MultiByteToWideChar(CP_UTF8,0,s.data(),(int)s.size(),nullptr,0);
    std::wstring w(n,L'\0'); MultiByteToWideChar(CP_UTF8,0,s.data(),(int)s.size(),w.data(),n); return w;
}
static bool writeBlob(const std::wstring& path, DxBlob* b) {
    FILE* f=_wfopen(path.c_str(),L"wb"); if(!f) return false;
    bool ok=std::fwrite(b->GetBufferPointer(),1,b->GetBufferSize(),f)==b->GetBufferSize(); return std::fclose(f)==0&&ok;
}
static std::string errorsOf(DxResult* r) {
    DxEncoding* e=nullptr; if(r) r->GetErrorBuffer(&e); if(!e) return {};
    std::string s(static_cast<const char*>(e->GetBufferPointer()),e->GetBufferSize()); e->Release();
    while(!s.empty()&&s.back()=='\0') s.pop_back(); return s;
}

// dxc.exe ARGS through IDxcCompiler3: -dumpbin IN -Fc OUT disassembles; otherwise the input file (the positional
// argument) is compiled with every argument as dxc.exe passes them, the object written to -Fo and the disassembly to -Fc
static int dxcJob(Utils* u, Compiler3* c, IncludeHandler* inc, const std::vector<std::wstring>& a, std::string& msg) {
    std::wstring in, fo, fc; bool dump=false;
    static const wchar_t* withValue[]={L"-T",L"-E",L"-Fo",L"-Fc",L"-D",L"-I",L"-HV",L"-Fe",L"-Fd",L"-Fre",L"-Frs",L"-Fsh"};
    for (size_t i=0;i<a.size();i++) {
        const std::wstring& s=a[i];
        bool takes=false; for (auto w:withValue) takes|=s==w;
        if (s==L"-dumpbin") dump=true;
        else if (takes&&i+1<a.size()) { if(s==L"-Fo") fo=a[i+1]; if(s==L"-Fc") fc=a[i+1]; i++; }
        else if (!s.empty()&&s[0]!=L'-'&&s[0]!=L'/') in=s;
    }
    if (in.empty()) { msg="no input file"; return 2; }
    uint32_t cp=0; DxEncoding* src=nullptr;
    if (u->LoadFile(in.c_str(),&cp,&src)<0||!src) { msg="cannot read the input file"; return 1; }
    int known=0; uint32_t enc=0; src->GetEncoding(&known,&enc);
    DxcBuffer buf{src->GetBufferPointer(),src->GetBufferSize(),known?enc:0u};
    int rc=0;
    if (dump) {
        DxResult* r=nullptr;
        if (c->Disassemble(&buf,kResultIid,reinterpret_cast<void**>(&r))<0||!r) { src->Release(); msg="disassemble failed"; return 1; }
        HR st=-1; r->GetStatus(&st); DxBlob* text=nullptr; r->GetResult(&text); msg=errorsOf(r);
        rc=st<0||!text?1:(fc.empty()||writeBlob(fc,text))?0:1;
        if(text) text->Release(); r->Release(); src->Release(); return rc;
    }
    // -Fo / -Fc are dxc.exe's own (the files it writes the results to), not the compiler's
    std::vector<const wchar_t*> args;
    for (size_t i=0;i<a.size();i++) { if ((a[i]==L"-Fo"||a[i]==L"-Fc")&&i+1<a.size()) { i++; continue; } args.push_back(a[i].c_str()); }
    DxResult2* r=nullptr;
    HR hr=c->Compile(&buf,args.data(),(uint32_t)args.size(),inc,kResultIid,reinterpret_cast<void**>(&r));
    src->Release();
    if (hr<0||!r) { msg="compile call failed"; return 1; }
    HR st=-1; r->GetStatus(&st); msg=errorsOf(r);
    if (st<0) { r->Release(); return 1; }
    auto put=[&](int kind,const std::wstring& path)->bool{
        if (path.empty()) return true;
        DxBlob* b=nullptr; DxBlobUtf16* name=nullptr;
        if (r->GetOutput(kind,kBlobIid,reinterpret_cast<void**>(&b),&name)<0||!b) { if(name) name->Release(); return false; }
        bool ok=writeBlob(path,b); b->Release(); if(name) name->Release(); return ok;
    };
    bool ok=put(kOutObject,fo);
    if (ok&&!fc.empty()) {
        if (r->HasOutput(kOutDisassembly)) ok=put(kOutDisassembly,fc);
        else {   // (the disassembly of the object, as dxc.exe writes it)
            DxBlob* obj=nullptr; ok=r->GetOutput(kOutObject,kBlobIid,reinterpret_cast<void**>(&obj),nullptr)>=0&&obj;
            if (ok) {
                DxcBuffer ob{obj->GetBufferPointer(),obj->GetBufferSize(),0}; DxResult* d=nullptr;
                ok=c->Disassemble(&ob,kResultIid,reinterpret_cast<void**>(&d))>=0&&d;
                DxBlob* text=nullptr; if(ok) d->GetResult(&text);
                ok=ok&&text&&writeBlob(fc,text);
                if(text) text->Release(); if(d) d->Release(); obj->Release();
            }
        }
    }
    r->Release();
    if (!ok&&msg.empty()) msg="cannot write the output";
    return ok?0:1;
}

static int toolMain(int argc,char** argv);

static int batch(const char* dll, void* library) {
    using Create=HR(*)(const Guid&,const Guid&,void**);
    auto create=reinterpret_cast<Create>(dlsym(library,"DxcCreateInstance"));
    const Guid uc={0x6245d6af,0x66e0,0x48fd,{0x80,0xb4,0x4d,0x27,0x17,0x96,0x74,0x8c}};
    const Guid ui={0x4605c4cb,0x2019,0x492a,{0xad,0xa4,0x65,0xf2,0x0b,0xb7,0xd6,0x7f}};
    const Guid cc={0x73e22d93,0xe6ce,0x47f3,{0xb5,0xbf,0xf0,0x66,0x4f,0x39,0xc1,0xb0}};
    const Guid ci={0x228b4687,0x5a6a,0x4730,{0x90,0x0c,0x97,0x02,0xb2,0x20,0x3f,0x54}};
    Utils* u=nullptr; Compiler3* c=nullptr; IncludeHandler* inc=nullptr;
    if (!create||create(uc,ui,reinterpret_cast<void**>(&u))<0||create(cc,ci,reinterpret_cast<void**>(&c))<0||
        u->CreateDefaultIncludeHandler(&inc)<0) return 3;
    std::string line;
    for (int ch; (ch=std::fgetc(stdin))!=EOF;) {
        if (ch!='\n') { if(ch!='\r') line+=(char)ch; continue; }
        std::vector<std::string> w; size_t p=0;
        for (size_t t; (t=line.find('\t',p))!=std::string::npos; p=t+1) w.push_back(line.substr(p,t-p));
        w.push_back(line.substr(p)); line.clear();
        std::string msg; int rc;
        if (w[0]=="dxc") {
            std::vector<std::wstring> a; for (size_t i=1;i<w.size();i++) a.push_back(widen(w[i]));
            rc=dxcJob(u,c,inc,a,msg);
        } else {   // assemble / validate / opt: the commands below
            std::vector<char*> av{const_cast<char*>("dxc_assemble"),const_cast<char*>(dll)};
            for (auto& s:w) av.push_back(s.data());
            g_msg=&msg; rc=toolMain((int)av.size(),av.data()); g_msg=nullptr;
        }
        for (auto& k:msg) if (k=='\n') k='\x1f'; else if (k=='\r') k=' ';
        std::printf("RC %d\t%s\n",rc,msg.c_str()); std::fflush(stdout);
    }
    return 0;
}

int main(int argc,char** argv) {
    if (argc==3&&std::string(argv[2])=="batch") {
        void* library=dlopen(argv[1],0);
        if (!library) {std::fprintf(stderr,"%s\n",dlerror());return 2;}
        return batch(argv[1],library);
    }
    return toolMain(argc,argv);
}
#define main toolMain
#endif
// usage also: dxc_assemble DLL opt IN OUT pass... (IDxcOptimizer: IN = bitcode or DXIL container, OUT = bitcode)
//             dxc_assemble DLL passes            (list optimizer passes and their arguments)
//             dxc_assemble DLL batch             (Windows: many jobs from stdin in one process, see above)
int main(int argc,char** argv) {
    std::string cmd=argc>2?argv[2]:"";
    void* library=argc>1?dlopen(argv[1],RTLD_NOW|RTLD_LOCAL):nullptr;
    if (!library) {std::fprintf(stderr,"%s\n",dlerror());return 2;}
    using Create=HR(*)(const Guid&,const Guid&,void**);
    auto create=reinterpret_cast<Create>(dlsym(library,"DxcCreateInstance"));
    if (!create) return 2;
    const Guid oc={0xae2cd79f,0xcc22,0x453f,{0x9b,0x6b,0xb1,0x24,0xe7,0xa5,0x20,0x4c}};
    const Guid oi={0x25740e2e,0x9cba,0x401b,{0x91,0x19,0x4f,0xb4,0x2f,0x39,0xf2,0x70}};
    if (cmd=="passes"||cmd=="opt") {
        Optimizer* o=nullptr; if(create(oc,oi,reinterpret_cast<void**>(&o))<0||!o) return 3;
        if (cmd=="passes") {
            uint32_t n=0; o->GetAvailablePassCount(&n);
            for (uint32_t i=0;i<n;i++) { OptPass* p=nullptr; if(o->GetAvailablePass(i,&p)<0||!p) continue; wchar_t* nm=nullptr; p->GetOptionName(&nm);
                uint32_t na=0; p->GetOptionArgCount(&na); std::wprintf(L"%ls", nm?nm:L"?");
                for (uint32_t k=0;k<na;k++){ wchar_t* an=nullptr; p->GetOptionArgName(k,&an); std::wprintf(L" %ls", an?an:L"?"); }
                std::wprintf(L"\n"); }
            return 0;
        }
        if (argc<5) return 2;
        DxInput input(argv[3]); if(input.bytes.empty()) return 2;
        std::vector<std::wstring> ws; for (int i=5;i<argc;i++){ std::string s(argv[i]); ws.emplace_back(s.begin(),s.end()); }
        std::vector<const wchar_t*> opts; for (auto& w:ws) opts.push_back(w.c_str());
        DxBlob* mod=nullptr; DxEncoding* text=nullptr;
        HR hr=o->RunOptimizer(&input,opts.data(),(uint32_t)opts.size(),&mod,&text);
        if (text&&text->GetBufferSize()) say(text->GetBufferPointer(),text->GetBufferSize());
        if (hr<0||!mod) {sayf("optimizer failed 0x%x\n",unsigned(hr));return 4;}
        std::ofstream f(argv[4],std::ios::binary); f.write(static_cast<const char*>(mod->GetBufferPointer()),mod->GetBufferSize());
        return f?0:6;
    }
    if (argc!=5 || (cmd!="assemble" && cmd!="validate")) return 2;
    DxInput input(argv[3]); if(input.bytes.empty()) return 2;
    const Guid ac={0xd728db68,0xf903,0x4f80,{0x94,0xcd,0xdc,0xcf,0x76,0xec,0x71,0x51}};
    const Guid ai={0x091f7a26,0x1c1f,0x4948,{0x90,0x4b,0xe6,0xe3,0xa8,0xa7,0x71,0xd5}};
    const Guid vc={0x8ca3e215,0xf728,0x4cf3,{0x8c,0xdd,0x88,0xaf,0x91,0x75,0x87,0xa1}};
    const Guid vi={0xa6e82bd2,0x1fd7,0x4826,{0x98,0x11,0x28,0x57,0xe7,0x97,0xf4,0x9a}};
    DxResult* result=nullptr; DxUnknown* owner=nullptr; HR hr;
    if(std::string(argv[2])=="assemble") {
        Assembler* a=nullptr; hr=create(ac,ai,reinterpret_cast<void**>(&a));
        if(hr<0 || !a)return 3;
        owner=a;hr=a->AssembleToContainer(&input,&result);
    } else {
        Validator* v=nullptr;hr=create(vc,vi,reinterpret_cast<void**>(&v));
        if(hr<0 || !v)return 3;
        owner=v;hr=v->Validate(&input,0,&result);
    }
    if(hr<0){sayf("call failed 0x%x\n",unsigned(hr));return 4;}
    DxBlob* blob=output(result);if(!blob)return 5;
    std::ofstream f(argv[4],std::ios::binary);
    f.write(static_cast<const char*>(blob->GetBufferPointer()),blob->GetBufferSize());
    bool good=bool(f);f.close();blob->Release();result->Release();owner->Release();
    return good?0:6;
}
