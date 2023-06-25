interface Props<T> {
  class?: string;
  name: string;
  value: T;
  children: React.ReactNode;
  checked?: boolean;
  onChange?: (value: T) => void;
}

export default function Radio<T>(props: Props<T>) {
  const className = () => {

  };
  return (
    <label class={[checked ? 'active' : '', className].join(' ')}>
      <input class="inset-0" type="radio" value={`${value}`} onChange={() => onChange?.(value)} />
    </label>
  );
}

// const Input = styled.label`
//   position: relative;
//   display: inline-flex;
//   align-items: center;
//   justify-content: center;
//   border-radius: ${s.radius['lg']};
//   padding: ${s.size['2']} ${s.size['4.5']};
//   cursor: pointer;
//   margin: ${s.size['2']} 0;
//   border: 1px solid ${({ theme }) => theme.gray400};

//   input {
//     position: absolute;
//     top: 0;
//     left: 0;
//     width: 1px;
//     height: 1px;
//     border: none;
//     overflow: hidden;
//     clip: rect(0px, 0px, 0px, 0px);
//   }

//   &:hover {
//     background: ${({ theme }) => transparentize(0.88, theme.green500)};
//     border-color: ${({ theme }) => theme.green500};
//   }

//   &.active {
//     background: ${({ theme }) => transparentize(0.45, theme.green500)};
//     border-color: ${({ theme }) => theme.green500};
//   }
// `;
