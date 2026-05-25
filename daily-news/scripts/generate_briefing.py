#!/usr/bin/env python3
import json
import sys
from datetime import datetime

def get_ngrams(text, n=3):
    """提取 n-gram 片段"""
    return [text[i:i+n] for i in range(len(text) - n + 1)]

def extract_key_phrases(text):
    """提取 4-5 字的关键短语"""
    phrases = []
    for n in [4, 5]:
        phrases.extend(get_ngrams(text, n))
    return phrases

def jaccard_similarity(list1, list2):
    """计算 Jaccard 相似度"""
    set1, set2 = set(list1), set(list2)
    if not set1 or not set2:
        return 0
    intersection = set1 & set2
    union = set1 | set2
    return len(intersection) / len(union) if union else 0

def is_similar(title1, title2):
    """
    三层判断新闻标题相似度
    第1层：前缀强匹配（前12字，2-gram，阈值0.7）
    第2层：关键短语匹配（4-5字片段，阈值0.3）
    第3层：全文 3-gram 匹配（阈值0.45）
    """
    if not title1 or not title2:
        return False
    if title1 == title2:
        return True

    # 第1层：前缀强匹配
    prefix_len = min(12, len(title1), len(title2))
    if prefix_len >= 8:
        prefix1 = title1[:prefix_len]
        prefix2 = title2[:prefix_len]
        prefix_grams1 = get_ngrams(prefix1, 2)
        prefix_grams2 = get_ngrams(prefix2, 2)
        prefix_sim = jaccard_similarity(prefix_grams1, prefix_grams2)
        if prefix_sim > 0.7:
            return True

    # 第2层：关键短语匹配
    phrases1 = extract_key_phrases(title1)
    phrases2 = extract_key_phrases(title2)
    phrase_sim = jaccard_similarity(phrases1, phrases2)
    if phrase_sim > 0.3:
        return True

    # 第3层：全文 3-gram 匹配
    grams1 = get_ngrams(title1, 3)
    grams2 = get_ngrams(title2, 3)
    similarity = jaccard_similarity(grams1, grams2)

    return similarity > 0.45

def editorial_pick(news_list, target=12):
    """
    智能采编新闻
    - 分层平衡采样：头条区 + 均衡区 + 捡漏区
    - 标题去重：避免同一事件的不同报道重复出现
    - 边界处理：新闻条数少时确保至少10-12条
    """
    if not news_list:
        return []
    
    # 按分数排序
    sorted_news = sorted(news_list, key=lambda x: x.get('score') or 0, reverse=True)
    
    selected = []
    seen_titles = []
    
    def add_news(item):
        """添加新闻，检查去重"""
        title = item.get('title', '').strip()
        if not title:
            return False
        # 检查是否与已选新闻相似
        for seen in seen_titles:
            if is_similar(title, seen):
                return False
        selected.append(item)
        seen_titles.append(title)
        return True
    
    # 边界情况：如果新闻总数较少（小于18条），使用简化逻辑
    if len(sorted_news) < 18:
        for news in sorted_news:
            if len(selected) >= target:
                break
            add_news(news)
        # 如果去重后不够目标数量，放宽相似度限制
        if len(selected) < target:
            for news in sorted_news:
                if len(selected) >= target:
                    break
                if news not in selected:
                    selected.append(news)
                    seen_titles.append(news.get('title', ''))
        return sorted(selected, key=lambda x: x.get('score', 0), reverse=True)[:target]
    
    # 正常情况：分层采样
    # 第一层：头条区（3条） - 全局分数最高的 Top 3
    headline_count = 0
    for news in sorted_news:
        if headline_count >= 3:
            break
        if add_news(news):
            headline_count += 1
    
    # 第二层：均衡区（6条） - 确保各分类都有代表
    # 先按分类整理
    categories = {}
    for news in sorted_news:
        cat = news.get('category', '其他')
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(news)
    
    # 从主要分类中各选至少1条
    priority_cats = ['时事', '国内', '国际', '商业']
    for cat in priority_cats:
        if cat in categories and categories[cat]:
            # 每个分类选择分数最高的一条（且未被选入的）
            for news in categories[cat]:
                if news not in selected:
                    if add_news(news):
                        break
    
    # 第三层：捡漏区 - 从剩余新闻中填充到目标数量
    for news in sorted_news:
        if len(selected) >= target:
            break
        if news not in selected:
            add_news(news)
    
    # 保底：如果还不够目标数量，放宽相似度限制
    if len(selected) < target:
        for news in sorted_news:
            if len(selected) >= target:
                break
            if news not in selected:
                selected.append(news)
                seen_titles.append(news.get('title', ''))
    
    # 最终按分数排序输出
    return sorted(selected, key=lambda x: x.get('score', 0), reverse=True)[:target]

def generate_text(data):
    if not data or data.get('code') != 200: return "无法获取新闻数据"
    d = data.get('data', {})
    cal = d.get('calendar', {})
    news_items = editorial_pick(d.get('newsList', []), 12)
    hist = d.get('historyList', [])[:3]
    ph = d.get('phrase', {})
    se = d.get('sentence', {})
    we = d.get('weather', {})
    res = []
    
    # 计算问候语
    solar_date = f"{cal.get('cMonth')}-{cal.get('cDay')}"
    lunar_date = f"{cal.get('lMonth')}-{cal.get('lDay')}"
    
    # 阳历节假日
    solar_holidays = {
        '1-1': '节日愉快',
        '5-1': '节日愉快',
        '10-1': '节日愉快',
        '10-2': '节日愉快',
        '10-3': '节日愉快',
        '10-4': '节日愉快',
        '10-5': '节日愉快',
        '10-6': '节日愉快',
        '10-7': '节日愉快'
    }
    
    # 农历节假日
    lunar_holidays = {
        '12-30': '节日愉快',
        '1-1': '节日愉快',
        '1-2': '节日愉快',
        '1-3': '节日愉快',
        '1-4': '节日愉快',
        '1-5': '节日愉快',
        '1-6': '节日愉快',
        '5-5': '端午安康',
        '8-15': '中秋愉快'
    }
    
    # 优先级：阳历节假日 > 农历节假日 > 工作日/周末
    greeting = solar_holidays.get(solar_date) or lunar_holidays.get(lunar_date)
    if not greeting:
        greeting = '周末愉快' if cal.get('nWeek', 1) >= 6 else '工作愉快'
    
    # 节气处理
    term_text = f"{cal.get('term')}，" if cal.get('isTerm') else ''
    
    res.append(f"慧语简报，{cal.get('cMonth')}月{cal.get('cDay')}日{cal.get('ncWeek')}，农历{cal.get('monthCn')}{cal.get('dayCn')}，{term_text}{greeting}，平安喜乐")
    res.append("")
    if we and we.get('detail'):
        wd = we.get('detail', {})
        # 判断是今天还是明天
        time_of_day = '今天' if we.get('weatherOf') == 'today' else '明天'
        city = we.get('city', '')
        
        # 天气状况：如果白天和夜间相同，只显示一次；否则用"转"连接
        text_day = wd.get('text_day', '')
        text_night = wd.get('text_night', '')
        weather_text = text_day
        if text_night and text_night != text_day:
            weather_text = f"{text_day}转{text_night}"
        
        # 温度
        temp = f"{wd.get('low', '')} ~ {wd.get('high', '')}℃"
        
        # 风力：等级<=3显示"微风"，否则显示详细信息
        wind_scale = int(wd.get('wind_scale', 0))
        if wind_scale <= 3:
            wind_text = '微风'
        else:
            wind_dir = wd.get('wind_direction', '')
            # 如果风向以"无"开头，不加"风"字
            wind_suffix = '' if wind_dir.startswith('无') else '风'
            wind_text = f"{wind_dir}{wind_suffix}{wind_scale}级"
        
        res.append(f"{time_of_day}{city}{weather_text}，{temp}，{wind_text}")
        res.append("")
    for i, n in enumerate(news_items, 1):
        res.append(f"{i}．{n.get('title', '').strip()}；")
    res.append("")
    if hist:
        res.append("【历史上的今天】")
        for h in hist: res.append(h.get('event'))
        res.append("")
    if ph:
        res.append("【天天成语】")
        res.append(ph.get('phrase', ''))
        res.append(f"释义：{ph.get('explain', '')}")
        if ph.get('from'): res.append(f"出处：{ph.get('from')}")
        res.append("")
    if se:
        res.append("【慧语香风】")
        res.append(se.get('sentence', ''))
        res[-1] += f" —— {se.get('author', '佚名')}"
        res.append("")
    cur = datetime.now()
    pass_d = (cur - datetime(cur.year, 1, 1)).days + 1
    tot_d = 366 if (cur.year % 4 == 0 and (cur.year % 100 != 0 or cur.year % 400 == 0)) else 365
    prog = min(round(pass_d / tot_d * 100, 2), 100)
    bar_len = 14
    filled = int(bar_len * prog / 100)
    bar = "▓" * filled + "░" * (bar_len - filled)
    res.append("【进度条】")
    res.append(f"{bar}")
    res.append(f"{cur.year}年，您已经使用了{prog}%")
    res.append("")
    res.append("(由 https://news.topurl.cn 采集整理)")
    return "\n".join(res)

def main():
    try:
        f = sys.stdin if len(sys.argv) < 2 else open(sys.argv[1], 'r', encoding='utf-8')
        print(generate_text(json.load(f)))
    except: pass

if __name__ == "__main__": main()
