import React from 'react';
import {AbsoluteFill, Composition, Img, staticFile, Easing, interpolate, registerRoot, useCurrentFrame} from 'remotion';

const purple = '#7516f8';
const muted = '#61596b';
const FileIcon = ({size = 42, color = purple}: {size?: number; color?: string}) => (
  <svg width={size} height={size} viewBox="0 0 48 48" fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round">
    <path d="M12 5h16l9 9v29H12zM28 5v10h9"/>
    <rect x="18" y="24" width="10" height="10" rx="1.5" fill={color} stroke="none"/>
    <path d="m28 27 6-3v10l-6-3z" fill={color} stroke="none"/>
  </svg>
);
const Button = ({children, outline = false}: {children: React.ReactNode; outline?: boolean}) => (
  <div style={{padding: '13px 24px', background: outline ? 'white' : purple, color: outline ? muted : 'white', border: outline ? '1px solid #ddd4e8' : '1px solid transparent', borderRadius: 12, fontSize: 14}}>{children}</div>
);
const Empty = () => (
  <div style={{position: 'absolute', inset: '0 0 64px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 24}}>
    <FileIcon color="#9860e9"/>
    <div style={{fontSize: 24, fontWeight: 600}}>Video hier ablegen</div>
    <Button>Datei auswählen</Button>
  </div>
);
const Demo = () => {
  const frame = useCurrentFrame();
  const reset = interpolate(frame, [216, 239], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const drag = interpolate(frame, [20, 58], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic)});
  const dropped = frame >= 61;
  const complete = frame >= 145;
  const progress = interpolate(frame, [76, 144], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const cursorX = 148 + drag * 390;
  const cursorY = 548 - drag * 260;
  return <AbsoluteFill style={{background: '#fcfcfe', color: '#1c1425', fontFamily: 'Arial, Helvetica, sans-serif'}}>
    <div style={{position: 'absolute', top: 25, left: 270, fontSize: 13, color: muted}}>Video Shrink</div>
    <div style={{position: 'absolute', left: 250, top: 60, width: 560, height: 560, border: `1px solid ${frame >= 45 && frame < 68 ? '#b995ef' : '#e8e3ef'}`, borderRadius: 20, background: 'white', overflow: 'hidden'}}>
      <div style={{opacity: dropped ? reset : 1}}><Empty/></div>
      {dropped && <div style={{position: 'absolute', inset: '65px 40px 100px', opacity: 1 - reset}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8}}><FileIcon size={28}/><span style={{fontSize: 15, fontWeight: 600}}>video.mp4</span><span style={{marginLeft: 'auto', color: muted}}>×</span></div>
        <div style={{fontSize: 13, color: muted}}>32 MB · 02:00 · 1920 × 1080</div>
        {complete ? <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 40, gap: 12}}>
          <svg width="40" height="40" viewBox="0 0 40 40" fill="none" stroke="#28794f" strokeWidth="2"><circle cx="20" cy="20" r="16"/><path d="m12 20 5 5 11-12"/></svg>
          <div style={{fontSize: 30, fontWeight: 700, marginTop: 4}}>32 MB → 4,8 MB</div>
          <div style={{fontSize: 13, color: muted}}>85 % kleiner · MP4 mit Ton</div>
          <div style={{display: 'flex', gap: 12, marginTop: 12}}><Button>Video öffnen</Button><Button outline>Ordner öffnen</Button></div>
          <div style={{fontSize: 13, color: purple, marginTop: 12}}>Nächstes Video auswählen</div>
        </div> : <div style={{paddingTop: 32}}>
          <div style={{display: 'flex', gap: 8}}>{['1280 × 720', '30 fps', 'Bis 15 MB'].map(label => <div key={label} style={{fontSize: 12, padding: '7px 10px', borderRadius: 8, background: '#f7f5fa', color: muted}}>{label}</div>)}</div>
          <div style={{fontSize: 14, fontWeight: 600, marginTop: 50}}>{frame < 76 ? 'Video wird analysiert …' : 'Video verkleinern'}</div>
          <div style={{height: 6, background: '#eee5fb', borderRadius: 4, marginTop: 16, overflow: 'hidden'}}><div style={{width: `${progress * 100}%`, height: '100%', background: purple}}/></div>
          <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 13, color: muted, marginTop: 14}}><span>{Math.floor(progress * 100)} %</span><span>Abbrechen</span></div>
        </div>}
      </div>}
      <div style={{position: 'absolute', bottom: 16, left: 24, right: 24, display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 12, color: muted}}>
        <span>⌄ &nbsp; Optionen</span><span style={{background: '#f7f5fa', padding: '7px 10px', borderRadius: 8}}><span style={{color: '#1c1425'}}>WhatsApp</span> · Automatisch</span>
      </div>
    </div>
    {!dropped && <div style={{position: 'absolute', left: 48 + drag * 390, top: 510 - drag * 260, width: 164, height: 72, display: 'flex', alignItems: 'center', gap: 10, background: 'white', border: '1px solid #e8e3ef', borderRadius: 12, padding: '12px', boxSizing: 'border-box', boxShadow: '0 8px 24px #2516370a', transform: `rotate(${-drag * 5}deg)`}}>
      <FileIcon size={32}/><div><div style={{fontSize: 13, fontWeight: 600}}>video.mp4</div><div style={{fontSize: 11, color: muted, marginTop: 4}}>32 MB</div></div>
    </div>}
    {frame < 79 && <svg width="28" height="36" viewBox="0 0 28 36" style={{position: 'absolute', left: cursorX, top: cursorY, opacity: frame > 65 ? (79 - frame) / 14 : 1}}><path d="m3 2 20 18-10 1-5 5 10z" fill="#211929" stroke="white" strokeWidth="2" strokeLinejoin="round"/></svg>}
    {reset > 0 && <div style={{position: 'absolute', left: 48, top: 510, width: 164, height: 72, display: 'flex', alignItems: 'center', gap: 10, background: 'white', border: '1px solid #e8e3ef', borderRadius: 12, padding: 12, boxSizing: 'border-box', opacity: reset}}><FileIcon size={32}/><div><div style={{fontSize: 13, fontWeight: 600}}>video.mp4</div><div style={{fontSize: 11, color: muted, marginTop: 4}}>32 MB</div></div></div>}
  </AbsoluteFill>;
};

registerRoot(() => <>
  <Composition id="Demo" component={Demo} durationInFrames={240} fps={24} width={1000} height={680}/>
  <Composition id="Cover" component={() => <Img src={staticFile('cover.svg')} style={{width: 1280, height: 220}}/>} durationInFrames={1} fps={1} width={1280} height={220}/>
</>);
