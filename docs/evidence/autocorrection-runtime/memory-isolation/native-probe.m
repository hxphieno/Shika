#import <Foundation/Foundation.h>
#import "SKRimeSession.h"
#import <mach/mach.h>
static uint64_t memory(void){ task_vm_info_data_t vm={0};mach_msg_type_number_t n=TASK_VM_INFO_COUNT; task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&vm,&n);return vm.phys_footprint; }
int main(int argc,char**argv){@autoreleasepool{setbuf(stdout,NULL);NSString*mode=@(argv[3]);printf("before %llu\n",memory());
SKRimeSession*s=[[SKRimeSession alloc]initWithSharedPath:@(argv[1]) userPath:@(argv[2]) schema:@"shika_flypy" error:nil];
SKRimeSession*p=[[SKRimeSession alloc]initWithSharedPath:@(argv[1]) userPath:@(argv[2]) schema:@"shika_flypy" error:nil];printf("init %llu\n",memory());
for(int i=1;i<=500;i++){@autoreleasepool{
 if([mode isEqual:@"schema"]){NSString*c=(i%2)?@"shika_pinyin":@"shika_flypy";[s selectSchema:c];[p selectSchema:c];}
 if([mode isEqual:@"query"]){[s replaceInput:@"nihc"];[s selectText:@"你好"];[p replaceInput:@"vsgo"];[s clearComposition];[p clearComposition];}
 if([mode isEqual:@"recreate"]){s=nil;p=nil;s=[[SKRimeSession alloc]initWithSharedPath:@(argv[1]) userPath:@(argv[2]) schema:(i%2)?@"shika_pinyin":@"shika_flypy" error:nil];p=[[SKRimeSession alloc]initWithSharedPath:@(argv[1]) userPath:@(argv[2]) schema:(i%2)?@"shika_pinyin":@"shika_flypy" error:nil];}
}if(i==1||i%20==0)printf("%d %llu\n",i,memory());}
s=nil;p=nil;printf("release %llu\n",memory());}return 0;}
