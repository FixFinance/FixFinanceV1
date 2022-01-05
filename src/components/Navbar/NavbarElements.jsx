import { FaBars } from 'react-icons/fa';
import { NavLink as Link } from 'react-router-dom';
import styled from 'styled-components';

export const Nav = styled.nav`
background: rgba(76, 175, 80, 0);
height: 85px;
display: flex;
justify-content: space-between;
padding: 0 50px 0 50px;
align-items: center;
`;

export const NavLink = styled(Link)`
color: #EDF0EB;
display: flex;
align-items: center;
text-decoration: none;
margin: 0 1rem;
height: 100%;
cursor: pointer;
&.active {
	color: #7D8282;
  border-bottom:1.8px solid #7D8282;
  padding-bottom: 5px;
  padding-top: 6.8px;
}
`;

export const Bars = styled(FaBars)`
display: none;
color: #808080;
@media screen and (max-width: 1050px) {
	display: block;
	position: absolute;
	top: 12px;
	right: 0;
	transform: translate(-100%, 75%);
	font-size: 1.8rem;
	cursor: pointer;
}
`;

export const NavMenu = styled.div`
display: flex;
align-items: center;
@media screen and (max-width: 1050px) {
	display: none;
}
`;

export const NavBtn = styled.nav`
display: flex;
align-items: center;
margin-right: 24px;
@media screen and (max-width: 1050px) {
	display: none;
}
`;

export const NavBtnLink = styled.button`
display: flex;
font-size: 14px;
background: ${props => props.black ? "#191A1A" : "#9DF368"};
color: ${props => props.black ? "#EDF0EB" : "#0F1010"};
border-radius: 110px;
width: 160px;
height: 50px;
justify-content: center;
align-items: center;
border: none;
cursor: pointer;
transition: all 0.2s ease-in-out;
&:hover {
	transition: all 0.2s ease-in-out;
  background: ${props => props.black ? "#3E4242" : "#CBF9AF"};
  color: ${props => props.black ? "#EDF0EB" : "#0F1010"};
}
`;

export const NavIcon = styled.div`
  display: flex;
  align-items: center;
` 