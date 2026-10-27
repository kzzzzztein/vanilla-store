/* Navigation, dropdowns, mobile menu, scroll reveal */
(()=>{const b=document.body,mq=matchMedia('(max-width:960px)'),page=location.pathname.split('/').pop()||'index.html';
document.querySelectorAll('.nav a').forEach(a=>{if(a.getAttribute('href')===page){a.setAttribute('aria-current','page');a.closest('.dd')?.querySelector('.dd-btn')?.classList.add('on')}});
const t=document.querySelector('.menu-toggle'),setMenu=o=>{b.classList.toggle('menu-open',o);t?.setAttribute('aria-expanded',o)};t?.addEventListener('click',()=>setMenu(!b.classList.contains('menu-open')));
document.querySelector('.backdrop')?.addEventListener('click',()=>setMenu(false));
const closeDD=()=>document.querySelectorAll('.dd.open').forEach(d=>{d.classList.remove('open');d.querySelector('[data-dd]')?.setAttribute('aria-expanded','false')});
document.querySelectorAll('[data-dd]').forEach(btn=>btn.addEventListener('click',e=>{if(btn.dataset.dd==='bag'&&(mq.matches||/cart|checkout/.test(page)))return location.href='cart.html';e.stopPropagation();const d=btn.closest('.dd'),o=!d.classList.contains('open');closeDD();d.classList.toggle('open',o);btn.setAttribute('aria-expanded',o)}));
document.addEventListener('click',e=>{if(!e.target.closest('.dd'))closeDD();if(e.target.closest('.nav a'))setMenu(false)});
document.addEventListener('keydown',e=>{if(e.key==='Escape'){closeDD();setMenu(false)}});mq.addEventListener?.('change',()=>setMenu(false));
const els=document.querySelectorAll('.reveal');if(!('IntersectionObserver'in window)){els.forEach(e=>e.classList.add('in'));return}
const io=new IntersectionObserver(es=>es.forEach(x=>{if(x.isIntersecting){x.target.classList.add('in');io.unobserve(x.target)}}),{threshold:.05});els.forEach(e=>io.observe(e))})();
