/** Only controlled diagnostic codes reach the UI; never display raw transport errors. */
export function learningCourseStatus(result?: {status:string;count:number;code?:string}):string {
 if(!result)return '尚未读取';
 if(result.status==='ok')return result.count===0?'暂无作业':`已读取 ${result.count} 份作业`;
 if(result.status==='partial')return `仅取得部分作业（${result.count} 份），可重试`;
 const hints:Record<string,string>={WORK_ENC:'未识别到作业入口，请打开官方页面核对',WORK_SCHEMA:'作业页面格式暂不兼容，请导出连接反馈',AUTH:'登录已过期，请重新连接',VERIFY:'需要完成验证码，请打开官方页面',RATE_LIMIT:'请求较频繁，请稍后再试',NETWORK:'网络读取失败，请重试',URL:'课程跳转地址暂不兼容，请导出连接反馈',REDIRECT:'课程跳转未完成，请打开官方页面核对',LIMIT:'课程内容超过处理范围，请导出连接反馈'};
 const code=result.code||'';
 if(hints[code])return `${hints[code]}（${code}）`;
 if(/^HTTP_[45]\d{2}$/.test(code))return `学习通请求失败（${code.replace('_',' ')}），可打开官方页面核对`;
 return '读取失败，请重试或导出连接反馈';
}
