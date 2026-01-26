#import "CLXMLParser.h"

@interface CLXMLParser () <NSXMLParserDelegate>

@property (nonatomic, strong) NSMutableArray *elementStack;      // 元素栈（存储元素名）
@property (nonatomic, strong) NSMutableArray *dictStack;         // 字典栈（存储嵌套的字典/数组）
@property (nonatomic, strong) NSMutableString *currentText;      // 当前文本内容
@property (nonatomic, strong) NSMutableDictionary *rootDict;     // 根字典

@end

@implementation CLXMLParser

#pragma mark - Public Methods

+ (NSDictionary *)parseXMLString:(NSString *)xmlString {
    if (!xmlString || xmlString.length == 0) {
        return @{};
    }
    
    CLXMLParser *parser = [[CLXMLParser alloc] init];
    return [parser parseToDict:xmlString];
}

+ (NSArray *)parseXMLArray:(NSString *)xmlString {
    if (!xmlString || xmlString.length == 0) {
        return @[];
    }
    
    CLXMLParser *parser = [[CLXMLParser alloc] init];
    NSDictionary *dict = [parser parseToDict:xmlString];
    
    // 将字典转换为数组格式（用于设备解析）
    return [parser convertDictToArray:dict];
}

#pragma mark - Private Parsing Methods

- (NSDictionary *)parseToDict:(NSString *)xmlString {
    self.elementStack = [NSMutableArray array];
    self.dictStack = [NSMutableArray array];
    self.currentText = [NSMutableString string];
    self.rootDict = [NSMutableDictionary dictionary];
    
    // 将根字典推入栈
    [self.dictStack addObject:self.rootDict];
    
    NSData *data = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @{};
    }
    
    NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:data];
    xmlParser.delegate = self;
    xmlParser.shouldProcessNamespaces = NO;
    xmlParser.shouldReportNamespacePrefixes = NO;
    [xmlParser parse];
    
    return self.rootDict;
}

- (NSArray *)convertDictToArray:(NSDictionary *)dict {
    NSMutableArray *result = [NSMutableArray array];
    
    // 递归查找 device 节点
    NSDictionary *deviceDict = [self findDeviceDict:dict];
    if (deviceDict) {
        [result addObject:deviceDict];
    }
    
    return result;
}

- (NSDictionary *)findDeviceDict:(NSDictionary *)dict {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    // 直接有 device 键
    if (dict[@"device"]) {
        id deviceValue = dict[@"device"];
        if ([deviceValue isKindOfClass:[NSDictionary class]]) {
            return [self processDeviceDict:deviceValue];
        }
    }
    
    // 递归查找
    for (NSString *key in dict) {
        id value = dict[key];
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSDictionary *found = [self findDeviceDict:value];
            if (found) {
                return found;
            }
        }
    }
    
    return nil;
}

- (NSDictionary *)processDeviceDict:(NSDictionary *)deviceDict {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    // 提取基本信息
    if (deviceDict[@"friendlyName"]) {
        result[@"friendlyName"] = deviceDict[@"friendlyName"];
    }
    if (deviceDict[@"modelName"]) {
        result[@"modelName"] = deviceDict[@"modelName"];
    }
    if (deviceDict[@"UDN"]) {
        result[@"UDN"] = deviceDict[@"UDN"];
    }
    if (deviceDict[@"manufacturer"]) {
        result[@"manufacturer"] = deviceDict[@"manufacturer"];
    }
    if (deviceDict[@"deviceType"]) {
        result[@"deviceType"] = deviceDict[@"deviceType"];
    }
    
    // 处理 serviceList
    id serviceList = deviceDict[@"serviceList"];
    if (serviceList) {
        NSMutableArray *serviceArray = [NSMutableArray array];
        
        if ([serviceList isKindOfClass:[NSDictionary class]]) {
            // serviceList 是字典，包含 service 键
            id services = serviceList[@"service"];
            if ([services isKindOfClass:[NSArray class]]) {
                // 多个 service
                for (NSDictionary *service in services) {
                    [serviceArray addObject:[self processService:service]];
                }
            } else if ([services isKindOfClass:[NSDictionary class]]) {
                // 单个 service
                [serviceArray addObject:[self processService:services]];
            }
        } else if ([serviceList isKindOfClass:[NSArray class]]) {
            // serviceList 直接是数组
            for (id item in serviceList) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [serviceArray addObject:[self processService:item]];
                }
            }
        }
        
        result[@"serviceList"] = serviceArray;
    }
    
    return result;
}

- (NSDictionary *)processService:(NSDictionary *)service {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    // 构建 service 标识字符串（用于匹配 AVTransport 和 RenderingControl）
    NSMutableString *serviceString = [NSMutableString string];
    if (service[@"serviceType"]) {
        [serviceString appendString:service[@"serviceType"]];
    }
    if (service[@"serviceId"]) {
        [serviceString appendFormat:@" %@", service[@"serviceId"]];
    }
    result[@"service"] = serviceString;
    
    // 构建 children 数组（包含所有服务属性）
    NSMutableArray *children = [NSMutableArray array];
    
    NSArray *keys = @[@"serviceType", @"serviceId", @"controlURL", @"eventSubURL", @"SCPDURL"];
    for (NSString *key in keys) {
        if (service[key]) {
            [children addObject:@{key: service[key]}];
        }
    }
    
    result[@"children"] = children;
    
    return result;
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI 
 qualifiedName:(NSString *)qName 
    attributes:(NSDictionary *)attributeDict {
    
    // 清空当前文本
    [self.currentText setString:@""];
    
    // 创建新的字典用于这个元素
    NSMutableDictionary *newDict = [NSMutableDictionary dictionary];
    
    // 添加属性（如果有）
    if (attributeDict.count > 0) {
        for (NSString *attrKey in attributeDict) {
            newDict[[@"@" stringByAppendingString:attrKey]] = attributeDict[attrKey];
        }
    }
    
    // 保存元素名和新字典到栈
    [self.elementStack addObject:elementName];
    [self.dictStack addObject:newDict];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentText appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI 
 qualifiedName:(NSString *)qName {
    
    if (self.elementStack.count == 0 || self.dictStack.count < 2) {
        return;
    }
    
    // 弹出当前元素
    [self.elementStack removeLastObject];
    NSMutableDictionary *currentDict = [self.dictStack lastObject];
    [self.dictStack removeLastObject];
    
    // 获取父容器
    NSMutableDictionary *parentDict = [self.dictStack lastObject];
    
    // 处理文本内容
    NSString *text = [self.currentText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    id valueToAdd;
    
    if (currentDict.count == 0) {
        // 纯文本节点
        if (text.length > 0) {
            valueToAdd = text;
        } else {
            valueToAdd = @"";
        }
    } else {
        // 有子元素的节点
        if (text.length > 0) {
            currentDict[@"#text"] = text;
        }
        valueToAdd = currentDict;
    }
    
    // 添加到父容器
    if (parentDict[elementName]) {
        // 已存在同名元素，转换为数组
        id existing = parentDict[elementName];
        if ([existing isKindOfClass:[NSMutableArray class]]) {
            [existing addObject:valueToAdd];
        } else {
            NSMutableArray *array = [NSMutableArray arrayWithObjects:existing, valueToAdd, nil];
            parentDict[elementName] = array;
        }
    } else {
        parentDict[elementName] = valueToAdd;
    }
    
    // 清空当前文本
    [self.currentText setString:@""];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    NSLog(@"CLXMLParser: XML parse error: %@", parseError.localizedDescription);
}

@end
