#include <rime_api.h>
#include <cstdio>
int main(int argc,char **argv) {
 if(argc != 3) return 2;
 auto api=rime_get_api(); RIME_STRUCT(RimeTraits,t);
 t.shared_data_dir=argv[1]; t.user_data_dir=argv[2]; t.app_name="rime.shika.deployer";
 t.min_log_level=2; t.log_dir="";
 api->setup(&t); api->initialize(&t); api->deployer_initialize(&t);
 bool ok=api->deploy(); api->finalize(); return ok?0:1;
}
