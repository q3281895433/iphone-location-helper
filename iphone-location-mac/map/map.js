'use strict';
(() => {
  const map = L.map('map', {zoomControl:false, maxZoom:19, minZoom:3, worldCopyJump:true}).setView([35,105],4);
  L.control.zoom({position:'topright'}).addTo(map);
  L.control.scale({imperial:false, position:'bottomright'}).addTo(map);
  let loadedTiles=0, errors=0, pick='start', locked=false, mode='polyline';
  let start=null, end=null, center=null, waypoints=[], trackConfig=null;
  const pins=L.layerGroup().addTo(map), route=L.polyline([], {color:'#087ef5',weight:5,opacity:.9}).addTo(map);
  const stadium=L.polyline([], {color:'#8b5acb',weight:4,opacity:.85}).addTo(map);
  const current=L.circleMarker([0,0],{radius:7,color:'#fff',weight:3,fillColor:'#137dff',fillOpacity:1});
  current.bindTooltip('已发送的模拟位置（非手机实时 GPS 读数）');
  let searchMarker=null, lastSearch=null;
  const tiles=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom:19, attribution:'&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank">OpenStreetMap</a> contributors'
  }).addTo(map);
  tiles.on('tileload',()=>{loadedTiles++;document.getElementById('network').textContent='OpenStreetMap · WGS84 · 可拖动标记微调位置';});
  tiles.on('tileerror',()=>{errors++;if(!loadedTiles)document.getElementById('network').textContent='底图暂未加载，请检查网络；不要凭空白底图选点。';});
  setTimeout(()=>{if(!loadedTiles)document.getElementById('network').textContent='底图加载较慢，请检查网络后缩放重试。';},12000);
  function send(item){if(window.webkit?.messageHandlers?.locationMap)window.webkit.messageHandlers.locationMap.postMessage(item);}
  function valid(p){return Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&Math.abs(p[0])<=85&&Math.abs(p[1])<=180;}
  function points(){return start&&end?[start,...waypoints,end]:[];}
  function distance(ps){return ps.slice(1).reduce((sum,p,i)=>sum+map.distance(ps[i],p),0);}
  function setPick(value){pick=value;document.querySelectorAll('[data-pick]').forEach(b=>b.classList.toggle('selected',b.dataset.pick===pick));renderHint();}
  function renderHint(){document.getElementById('hint').textContent=locked?'路线运行中，选点已锁定':({start:'点击地图设置起点',end:'点击地图设置终点',waypoint:'点击地图添加途经点（按点击顺序）',center:'点击地图设置固定点 / 跑道中心'})[pick];}
  function pin(p,text,kind,onMove){if(!p)return;const marker=L.marker(p,{draggable:!locked,icon:L.divIcon({className:'pin '+kind,html:text,iconSize:[31,31],iconAnchor:[15,15]})}).addTo(pins);marker.bindTooltip(kind==='start'?'起点':kind==='end'?'终点':kind==='center'?'固定点 / 跑道中心':'途经点 '+text);marker.on('dragend',()=>{const q=marker.getLatLng().wrap();const v=[q.lat,q.lng];if(valid(v)){onMove(v);redraw(true);}else redraw(false);});}
  function redraw(notify){
    pins.clearLayers();pin(start,'起','start',p=>start=p);pin(end,'终','end',p=>end=p);
    waypoints.forEach((p,i)=>pin(p,String(i+1),'waypoint',v=>waypoints[i]=v));
    if(mode==='stadium'||pick==='center')pin(center,'点','center',p=>{center=p;send({type:'coordinate',point:p});});
    route.setLatLngs(mode==='polyline'?points():[]);
    const length=distance(points());
    document.getElementById('summary').textContent=start&&end?`路线 ${(length/1000).toFixed(2)} km · ${waypoints.length} 个途经点 · 按选点连线，不自动沿道路规划`:'先选起点，再选终点；沿道路补充途经点。';
    document.getElementById('undo').disabled=locked||(!start&&!end&&!waypoints.length);
    if(notify)send({type:'route',points:points(),distance:length,start:start,end:end});
  }
  function choose(p){if(locked||!valid(p))return;if(pick==='center'){center=p;send({type:'coordinate',point:p});}else if(pick==='start'){start=p;setPick('end');}else if(pick==='end'){end=p;setPick('waypoint');}else{if(!start||!end){setPick(!start?'start':'end');return;}if(waypoints.length>=1998)return;waypoints.push(p);}redraw(true);}
  map.on('click',e=>{const p=e.latlng.wrap();choose([p.lat,p.lng]);});
  document.querySelectorAll('[data-pick]').forEach(b=>b.addEventListener('click',()=>{setPick(b.dataset.pick);redraw(false);}));
  document.getElementById('clear').onclick=()=>{if(locked)return;start=end=null;waypoints=[];setPick('start');redraw(true);};
  document.getElementById('undo').onclick=()=>{if(locked)return;if(waypoints.length)waypoints.pop();else if(end)end=null;else start=null;redraw(true);};
  document.getElementById('fit').onclick=()=>{const ps=mode==='stadium'?stadium.getLatLngs():points();if(ps.length>1)map.fitBounds(L.latLngBounds(ps),{padding:[65,90],maxZoom:18});};
  function stadiumPoints(c){
    if(!c||![c.latitude,c.longitude,c.lapLength,c.radius,c.rotation].every(Number.isFinite)||c.radius<=0||2*Math.PI*c.radius>=c.lapLength)return [];
    const straight=(c.lapLength-2*Math.PI*c.radius)/2, r=c.radius, turn=c.rotation*Math.PI/180, lat=c.latitude*Math.PI/180,lon=c.longitude*Math.PI/180;
    return Array.from({length:181},(_,i)=>{let d=i/180*c.lapLength;if(c.reverse)d=(c.lapLength-d)%c.lapLength;let x,y;
      if(d<=straight){x=r;y=-straight/2+d;}else if(d<=straight+Math.PI*r){const a=(d-straight)/r;x=r*Math.cos(a);y=straight/2+r*Math.sin(a);}else if(d<=2*straight+Math.PI*r){x=-r;y=straight/2-(d-straight-Math.PI*r);}else{const a=Math.PI+(d-2*straight-Math.PI*r)/r;x=r*Math.cos(a);y=-straight/2+r*Math.sin(a);}
      const east=x*Math.cos(turn)+y*Math.sin(turn),north=-x*Math.sin(turn)+y*Math.cos(turn),angle=Math.hypot(east,north)/6371008.8,bearing=Math.atan2(east,north);
      const a=Math.asin(Math.sin(lat)*Math.cos(angle)+Math.cos(lat)*Math.sin(angle)*Math.cos(bearing));const b=lon+Math.atan2(Math.sin(bearing)*Math.sin(angle)*Math.cos(lat),Math.cos(angle)-Math.sin(lat)*Math.sin(a));return[a*180/Math.PI,(b*180/Math.PI+540)%360-180];});
  }
  window.locationMap={
    update(data){if(data.mode){mode=data.mode;}if(data.track){trackConfig=data.track;center=[data.track.latitude,data.track.longitude];}stadium.setLatLngs(mode==='stadium'?stadiumPoints(trackConfig):[]);redraw(false);},
    center(p){if(valid(p))map.setView(p,17);},
    searchResult(data){if(!valid(data.point))return;lastSearch=data.point;if(searchMarker)map.removeLayer(searchMarker);searchMarker=L.circleMarker(data.point,{radius:8,color:'#fff',weight:3,fillColor:'#ed9634',fillOpacity:1}).addTo(map);const text=document.createElement('span');text.textContent=String(data.name||'搜索结果');searchMarker.bindTooltip(text);map.setView(data.point,16);},
    searchCheck(){return {hasMarker:!!searchMarker,point:lastSearch,zoom:map.getZoom()};},
    lock(value){locked=value;document.querySelectorAll('.toolbar button').forEach(b=>{if(b.id!=='fit')b.disabled=locked;});renderHint();redraw(false);},
    position(p){if(valid(p))current.setLatLng(p).addTo(map);else map.removeLayer(current);},
    check(){
      const results=[];const assert=(name,ok)=>results.push({name,ok:!!ok});
      map.setView([39.99,116.39],16);document.getElementById('clear').click();setPick('start');map.fire('click',{latlng:L.latLng(39.99,116.39)});map.fire('click',{latlng:L.latLng(39.992,116.394)});
      assert('select-start-end',points().length===2&&route.getLatLngs().length===2);
      assert('start-marker-unobscured',!pins.getLayers().some(p=>p.options.icon.options.className.includes('center')));
      setPick('waypoint');map.fire('click',{latlng:L.latLng(39.99,116.394)});assert('waypoint-order',Math.abs(points()[1][1]-116.394)<1e-9&&points()[2][0]===39.992);
      const before=JSON.stringify(points());this.lock(true);map.fire('click',{latlng:L.latLng(31,122)});assert('running-lock',before===JSON.stringify(points()));this.lock(false);
      document.getElementById('undo').click();assert('undo-waypoint',points().length===2);
      const endMarker=pins.getLayers().find(p=>p.options.icon.options.className.includes('end'));endMarker.setLatLng([39.9921,116.3941]);endMarker.fire('dragend');assert('drag-endpoint-updates-route',Math.abs(points().at(-1)[0]-39.9921)<1e-9&&Math.abs(route.getLatLngs().at(-1).lng-116.3941)<1e-9);
      this.update({mode:'stadium',track:{latitude:39.99,longitude:116.39,lapLength:400,radius:36.5,rotation:0,reverse:false}});assert('stadium-overlay',stadium.getLatLngs().length===181&&route.getLatLngs().length===0);
      this.update({mode:'polyline'});assert('route-preserved-across-modes',points().length===2&&route.getLatLngs().length===2);
      return {results,loadedTiles,tileErrors:errors,routeDistance:distance(points()),leaflet:L.version};
    }
  };
  new ResizeObserver(()=>map.invalidateSize()).observe(document.getElementById('map'));
  renderHint();send({type:'ready'});
})();
