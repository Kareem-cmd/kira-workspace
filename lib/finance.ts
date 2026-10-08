import {totals,type Row} from './model.ts';
export type FinanceRow={id:string;version:number;data:{kind:string;title:string;amount:number;currency:string;date:string;due:string;status:string;paidDate:string;employee:string;category:string;notes:string}};
export function financeSummary(entries:FinanceRow[],rows:Row[],month:string,currency:string){
 const all=entries.filter(r=>r.data.currency===currency&&r.data.status!=='void'),inMonth=(date:string)=>!month||date?.startsWith(month);
 const period=all.filter(r=>inMonth(r.data.date));
 const invoices=rows.filter(r=>r.kind==='document'&&r.data.docKind==='invoice'&&r.data.status==='صادر'&&r.data.currency===currency);
 const payments=rows.filter(r=>r.kind==='payment'&&invoices.some(d=>d.id===r.data.documentId));
 const sum=(rs:FinanceRow[])=>rs.reduce((n,r)=>n+r.data.amount,0);
 const revenue=invoices.filter(r=>inMonth(r.data.date)).reduce((n,r)=>n+totals(r.data).net,0)+sum(period.filter(r=>r.data.kind==='income'));
 const expenses=sum(period.filter(r=>['expense','salary'].includes(r.data.kind)));
 const incoming=payments.filter(r=>inMonth(r.data.date)).reduce((n,r)=>n+r.data.amount,0)+sum(all.filter(r=>r.data.kind==='income'&&r.data.status==='paid'&&inMonth(r.data.paidDate)));
 const outgoing=sum(all.filter(r=>r.data.kind!=='income'&&r.data.status==='paid'&&inMonth(r.data.paidDate)));
 const receivables=invoices.reduce((n,d)=>n+Math.max(0,totals(d.data).total-payments.filter(p=>p.data.documentId===d.id).reduce((s,p)=>s+p.data.amount,0)),0)+sum(all.filter(r=>r.data.kind==='income'&&r.data.status==='pending'));
 return {revenue,expenses,profit:revenue-expenses,incoming,outgoing,cash:incoming-outgoing,receivables,payables:sum(all.filter(r=>r.data.kind!=='income'&&r.data.status==='pending')),assets:sum(all.filter(r=>r.data.kind==='asset')),period,invoices,payments};
}
