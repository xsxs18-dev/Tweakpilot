#import <Foundation/Foundation.h>

#if __has_include(<roothide.h>)
#include <roothide.h>
#define TPJBRoot(path) jbroot(path)
#else
static inline NSString *TPJBRoot(NSString *path) {
	return [@"/var/jb" stringByAppendingPathComponent:path];
}
#endif
